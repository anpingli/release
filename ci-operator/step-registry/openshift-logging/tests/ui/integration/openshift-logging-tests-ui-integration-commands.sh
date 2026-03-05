#!/bin/bash
set -o nounset
set -o pipefail

# This script is designed to run as a step in Prow CI (OpenShift CI) jobs.
# We intentionally use 'exit 0' instead of 'exit 1' for failures to prevent
# blocking subsequent test steps in the CI pipeline. When a step exits with
# a non-zero code, the job stops and doesn't proceed to run subsequent steps.
# Since we're adding multiple test steps for different components, we want
# all steps to run regardless of individual step failures. Test failures
# can still be identified and analyzed through junit reports which are
# stored in the artifact directory and job status. A final step can be added 
# to parse the junit reports and fail the job if any tests fail.
#

BRANCH="main"

#set the correct logging-view-plugin branch according to the OpenShift Server Version
function setUIBranchName() {
  #majorVer=$(oc version -o json |jq -r '.serverVersion.major')
  minorVer=$(oc version -o json |jq -r '.serverVersion.minor')
  case $minorVe in
    25|26|27)
      echo "use branch release-6.0 for Patternfly4"
      BRANCH="release-6.0"
      ;;
    *)
      echo "use branch release-6.1 for Patternfly5"
      BRANCH="release-6.1"
      ;;
  esac 
}

function enableDevConsole() {
}

# Set proxy vars.
if [ -f "${SHARED_DIR}/proxy-conf.sh" ] ; then
  source "${SHARED_DIR}/proxy-conf.sh"
fi

## skip all tests when console is not installed.
if ! (oc get clusteroperator console --kubeconfig=${KUBECONFIG}) ; then
  echo "console is not installed, skipping all console tests."
  exit 0
fi

# Function to copy artifacts to the artifact directory after test run.
function copyArtifacts {
  if [ -d "gui_test_screenshots" ]; then
    # Copy JUnit files directly to ARTIFACT_DIR with a unique name for BigQuery ingestion
    cp gui_test_screenshots/junit_cypress-*.xml "${ARTIFACT_DIR}/junit_distributed-tracing-console-plugin.xml" 2>/dev/null || true
    # Remove the duplicate junit file from gui_test_screenshots before copying to artifact dir
    rm -f gui_test_screenshots/junit_cypress-*.xml 2>/dev/null || true
    cp -r gui_test_screenshots "${ARTIFACT_DIR}/gui_test_screenshots"
    echo "Artifacts copied successfully."
  else
    echo "Directory gui_test_screenshots does not exist. Nothing to copy."
  fi
}

# Copy the artifacts to the aritfact directory at the end of the test run.
trap copyArtifacts EXIT

# Validate KUBECONFIG
if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "Error: KUBECONFIG variable is not set"
  exit 0
fi

if [[ ! -f "${KUBECONFIG}" ]]; then
  echo "Error: Kubeconfig file ${KUBECONFIG} does not exist"
  exit 0
fi

# Set Kubeconfig var for Cypress.
export CYPRESS_KUBECONFIG_PATH=$KUBECONFIG
setUIBranchName
enableDevConsole

# Define the repository URL and target directory
echo "Download logging-view-plugin code"
repo_url="https://github.com/openshift/logging-view-plugin.git"
target_dir="/tmp/logging-ui-plugin"

# Clone the repository (uses main branch by default)
echo "Cloning the repository."
git clone "$repo_url" "$target_dir"
if [ $? -eq 0 ]; then
  cd "$target_dir/tests" || exit 0
  echo "Successfully cloned the repository and changed directory to $target_dir/tests."
else
  echo "Error cloning the repository."
  exit 0
fi
cd $target_dir
git checkout $BRANCH
sh web/cypress/e2e/run-cypress-logging.sh || exit 0
