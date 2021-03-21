# ghes-hotpatch-validator
Bash script to validate hotpatching of GitHub Enterprise Server post-installation. This will not work for full feature release upgrades (e.g. 2.19.14 to 2.20.10) as it first confirms the status of the upgrade based on the `hotpatch.log` file which should be present on all nodes.

# Usage

Copy this script to any server in your GitHub Enterprise Server environment, and run it with the following command:

`ghe-cluster-check-hotpatch <version>`

Or for a standalone installation, run the following command:

`ghe-check-hotpatch <version>`

### Examples

   This will validate a full cluster/HA hotpatch to 2.17.15
     `$ ghe-cluster-check-hotpatch 2.17.15`

   This will validate a standalone server hotpatch to 2.19.18
     `$ ghe-check-hotpatch 2.19.18`

# Notes

- For GitHub Enterprise Server 2.x this is primarily focused on validation of the GitHub centric processes ("Unicorns") which handle all API activity and user request processing.
  - When run on GitHub Enterprise Server 3.x it will verify all running containerized services.
- This is provided as-is, and should be used in combination with other sanity checks implemented for your deployment.
