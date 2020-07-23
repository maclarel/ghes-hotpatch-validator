#!/bin/bash
#/ Usage: ghe-cluster-check-hotpatch <version>
#/
#/ Reviews upgrade status of all nodes on the cluster to ensure successful hotpatch
#/
#/ EXAMPLES:
#/
#/    This will validate a hotpatch to 2.17.15
#/      $ ghe-cluster-check-hotpatch 2.17.15
#/
set -e

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  grep '^#/' <"$0" | cut -c 4-
  exit 2
fi

PATCH_VERSION=$1

# Validate that a version has been provided
if [ -z $1 ]
then
  echo "Please provide a version, e.g. ghe-cluster-check-hotpatch 2.17.15"
  exit 1
fi

sanity_check () {
# Confirm that this is an HA or Cluster setup.

  if [ ! -f /data/user/common/cluster.conf ]
  then
    echo "ERROR: This appears to be a standalone instance. Run ghe-check-hotpatch instead!"
    exit 1
  fi

# Verify that a hotpatch has at least been run, and that this isn't running
# against a feature release upgrade.

  if [ ! -f /data/user/patch/$PATCH_VERSION/hotpatch.log ]
  then
    echo "ERROR: Hotpatch log not found for" $PATCH_VERSION". Are you sure you specified the right version?"
    exit 1
  fi

# Verify that the same major version is reported to help rule out typos or
# attempting to run against feature release upgrades.

  GHES_HOSTNAME=$(grep github-hostname /data/user/common/github.conf | awk '{print $3}')
  API_VERSION=$(curl -s http://localhost:1337/api/v3/meta | jq .installed_version | tr '"' ' ' | xargs)

  if [[ ! "$PATCH_VERSION" == "$API_VERSION" ]]
  then
    echo "ERROR: API is reporting a different version than expected from command."
    echo "Specified version:" $PATCH_VERSION
    echo "API reporting:" $API_VERSION
    exit 1
  fi
}

get_hosts () {
# Create variable with all hosts in the cluster (from ghe-cluster-nodes).
# This is to facilitate SSH operations, as ghe-cluster-each will
# return all output in a block, rather than letting us go line by line.
# This really just simplifies text parsing.

  ALL_HOSTS=$(ghe-cluster-nodes)
}

check_log () {
# Grab the last line of the upgrade log on all nodes to confirm if the upgrade
# completed or not.

  echo "Checking upgrade status across all nodes:"
  echo
  for h in $ALL_HOSTS; do
    LAST_LOG_LINE=$(ssh ${h} tail -n1 /data/user/patch/$PATCH_VERSION/hotpatch.log)
    if [[ "$LAST_LOG_LINE" == *"is now patched"* ]]
    then
      echo ${h} "upgrade completed successfully. Last line:" $LAST_LOG_LINE
    else
      echo "ERROR: Upgrade did not fully complete on" ${h}!
      export FAILURE_STATUS=true
    fi
  done
  echo
}

get_current_symlink () {
# Output all current symlink information to validate that rollover has
# or has not occurred.

  echo "Checking that the /data/github/current symlink is updated:"
  echo
  for h in $ALL_HOSTS; do
    NEWEST_HASH=$(ssh ${h} 'ls -t /data/github/ | grep -v current | head -n1')
    CURRENT_SYMLINK=$(ssh ${h} ls -l /data/github/current | awk '{print $11}')
    if [[ "$CURRENT_SYMLINK" == *"$NEWEST_HASH" ]]
    then
      echo ${h} "has the correct symlink. Current symlink:" $CURRENT_SYMLINK "Expected hash:" $NEWEST_HASH
    else
      echo "ERROR: The symlink on" ${h} "is not pointing to the newest hash!"
      export FAILURE_STATUS=true
    fi
  done
  echo
}

check_running_hash () {
# Get the *newest* hash from /data/github, and compare the hash in the
# currently running Unicorn processes to it in order to validate rollover.
# This specifically excludes validation of Slumlord due to it using a different
# hash, and rarely being seen in the wild.

  echo "Checking that the Unicorn processes are running on the correct hash:"
  for h in $ALL_HOSTS; do
    NEWEST_HASH=$(ssh ${h} 'ls -t /data/github/ | grep -v current | head -n1 | cut -c 1-7')
    for p in $(ssh ${h} ps aux | grep ^git | grep -v slumlord | grep reqs | awk '{print $12}'); do
      if [[ "${p}" == *"$NEWEST_HASH"* ]]
      then
        echo "Unicorn processes on ${h} are on the latest hash. Showing:" ${p} "Expected hash:" $NEWEST_HASH
      else
        echo "ERROR: Unicorn processes on" ${h} "are NOT on the latest hash! Showing:" ${p} "Expected hash:" $NEWEST_HASH
        export FAILURE_STATUS=true
      fi
    done
  done
  echo
}

exit_status () {
# Inform user of any final errors, or success.

  if [ $FAILURE_STATUS ]
  then
    echo "!!!"
    echo "ERROR: Problems were encountered validating the upgrade. Please review the output above!"
    echo "!!!"
    exit 1
  else
    echo "Upgrade to" $PATCH_VERSION "appears to have completed successfully!"
    exit 0
  fi
}

main () {
  sanity_check
  get_hosts
  check_log
  get_current_symlink
  check_running_hash
  exit_status
}

main
