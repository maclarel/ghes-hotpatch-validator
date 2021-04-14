#!/bin/bash
#/ Usage: ghe-check-hotpatch <version>
#/
#/ Reviews upgrade status of a standalone deployment to confirm a successful hotpatch
#/
#/ EXAMPLES:
#/
#/    This will validate a hotpatch to 2.17.15
#/      $ ghe-check-hotpatch 2.17.15
#/
set -e

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  grep '^#/' <"$0" | cut -c 4-
  exit 2
fi

# Grab arg/init failure status
PATCH_VERSION=$1
FAILURE_STATUS=

# Validate that a version has been provided
if [ -z "$1" ]
then
  echo "Please provide a version, e.g. ghe-check-hotpatch.sh 2.17.15"
  exit 1
fi

# Set FEATURE_RELEASE variable to indicate that we're working with GHES 3.x
if [[ "$PATCH_VERSION" =~ 3.[0-9]+.[0-9]+ ]]
then
  FEATURE_RELEASE=3
else
  FEATURE_RELEASE=2
fi

sanity_check () {
# Confirm that this is an HA or Cluster setup.

  if [ -f /data/user/common/cluster.conf ]
  then
    echo "ERROR: This appears to be a cluster/HA instance. Run ghe-cluster-check-hotpatch instead!"
    exit 1
  fi

# Verify that a hotpatch has at least been run, and that this isn't running
# against a feature release upgrade.

  if [ ! -f /data/user/patch/"$PATCH_VERSION"/hotpatch.log ]
  then
    echo "ERROR: Hotpatch log not found for $PATCH_VERSION. Are you sure you specified the right version?"
    exit 1
  fi

# Verify that the same major version is reported to help rule out typos or
# attempting to run against feature release upgrades.

  API_VERSION=$(curl -s http://localhost:1337/api/v3/meta | jq .installed_version | tr '"' ' ' | xargs)

  echo "Checking if API version matches expected version:"
  if [[ "$PATCH_VERSION" == "$API_VERSION" ]]
  then
    echo "API version matches expected version."
  else
    echo "ERROR: API is reporting a different major version than specified in command."
    echo "Specified version: $PATCH_VERSION"
    echo "API reporting: $API_VERSION"
    export FAILURE_STATUS=true
  fi
  echo
}

check_log () {
# Grab the last line of the upgrade log on all nodes to confirm if the upgrade
# completed or not.

  echo "Checking upgrade status"
  LAST_LOG_LINE=$(tail -n1 /data/user/patch/"$PATCH_VERSION"/hotpatch.log)
  if [[ "$LAST_LOG_LINE" == *"is now patched"* ]]
  then
    echo "Upgrade completed successfully. Last line: $LAST_LOG_LINE"
  else
    echo "ERROR: Upgrade did not fully complete!"
    export FAILURE_STATUS=true
  fi
  echo
}

verify_running_image_tags () {
# Get the running, and expected, hashes for all containerized service
# and verify if they match.
  
  echo "Checking that all containers are running on their correct versions:"
  for s in $(docker ps -q | xargs docker inspect --format='{{.Config.Image}}' | awk -F ':' '{print $1}' | sort -u); do
    RUNNING_TAG=$(docker ps | grep "$s" | awk '{print $2}' | cut -d':' -f2 | sort -u)
    EXPECTED_TAG=$(sudo cat /data/user/docker/image/overlay2/repositories.json | jq .Repositories | grep "$s:" | head -n1 | awk -F'\"' '{print $2}' | cut -d':' -f2)

    # Verify that we're only running *one* unique hash per service
    # to avoid duplicate containers
    NUM_RUNNING_HASHES_FOR_SERVICE=$(echo "$RUNNING_TAG" | wc -w)
    if [ "$NUM_RUNNING_HASHES_FOR_SERVICE" -gt 1 ]
    then 
      echo "ERROR: More than 1 running hash for service $s! Got: $NUM_RUNNING_HASHES_FOR_SERVICE Expected: 1."
      export FAILURE_STATUS=true 
    fi

    # Verify that we're seeing the correct hash running
    if [ "$RUNNING_TAG" == "$EXPECTED_TAG" ]
    then 
      echo "$s is running on the expected hash."
    else
      echo "$s is running on the wrong hash! Got: $RUNNING_TAG Expected: $EXPECTED_TAG!"
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
  NEWEST_HASH=$(ls -t /data/github/ | grep -v current | head -n1)
  CURRENT_SYMLINK=$(ls -l /data/github/current | awk '{print $11}')
  if [[ "$CURRENT_SYMLINK" == *"$NEWEST_HASH" ]]
  then
    echo "This server has the correct symlink. Current symlink: $CURRENT_SYMLINK Expected hash: $NEWEST_HASH"
  else
    echo "ERROR: The symlink is not pointing to the newest hash!"
    export FAILURE_STATUS=true
  fi
  echo
}

check_running_hash () {
# Get the *newest* hash from /data/github, and compare the hash in the
# currently running Unicorn processes to it in order to validate rollover.
# This specifically excludes validation of Slumlord due to it using a different
# hash, and rarely being seen in the wild.

  echo "Checking that the Unicorn processes are running on the correct hash:"
  NEWEST_HASH=$(ls -t /data/github/ | grep -v current | head -n1 | cut -c 1-7)
  for p in $(ps aux | grep ^git | grep -v slumlord | grep reqs | awk '{print $12}'); do
    if [[ "${p}" == *"$NEWEST_HASH"* ]]
    then
      echo "Unicorn processes are on the latest hash. Showing: ${p} Expected hash: $NEWEST_HASH"
    else
      echo "ERROR: Unicorn processes are NOT on the latest hash! Showing: ${p} Expected hash: $NEWEST_HASH"
      export FAILURE_STATUS=true
    fi
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
    echo "Upgrade to $PATCH_VERSION appears to have completed successfully!"
    exit 0
  fi
}

main () {
  sanity_check
  check_log
  if [ "$FEATURE_RELEASE" -eq 3 ];
  then
    verify_running_image_tags
  else
    get_current_symlink
    check_running_hash
  fi
  exit_status
}

main
