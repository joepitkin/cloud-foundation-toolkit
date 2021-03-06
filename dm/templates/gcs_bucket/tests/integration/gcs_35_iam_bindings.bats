#!/usr/bin/env bats

source tests/helpers.bash

TEST_NAME=$(basename "${BATS_TEST_FILENAME}" | cut -d '.' -f 1)

export TEST_SERVICE_ACCOUNT="test-gcs-iam-sa-${RAND}"

########## HELPER FUNCTIONS ##########


# Create a random 10-char string and save it in a file.
RANDOM_FILE="/tmp/${CLOUD_FOUNDATION_ORGANIZATION_ID}-${TEST_NAME}.txt"
if [[ ! -e "${RANDOM_FILE}" ]]; then
    RAND=$(head /dev/urandom | LC_ALL=C tr -dc a-z0-9 | head -c 10)
    echo ${RAND} > "${RANDOM_FILE}"
fi

# Set variables based on the random string saved in the file.
# envsubst requires all variables used in the example/config to be exported.
if [[ -e "${RANDOM_FILE}" ]]; then
    export RAND=$(cat "${RANDOM_FILE}")
    DEPLOYMENT_NAME="${CLOUD_FOUNDATION_PROJECT_ID}-${TEST_NAME}-${RAND}"
    # Replace underscores in the deployment name with dashes.
    DEPLOYMENT_NAME=${DEPLOYMENT_NAME//_/-}
    CONFIG=".${DEPLOYMENT_NAME}.yaml"
    # Test specific variables:
    export BUCKET_NAME="test-bucket-${RAND}"
    export ROLE="roles/storage.objectViewer"
fi

########## HELPER FUNCTIONS ##########

function create_config() {
    echo "Creating ${CONFIG}"
    envsubst < ${BATS_TEST_DIRNAME}/${TEST_NAME}.yaml > "${CONFIG}"
}

function delete_config() {
    echo "Deleting ${CONFIG}"
    rm -f "${CONFIG}"
}

function setup() {
    # Global setup; executed once per test file.
    if [ ${BATS_TEST_NUMBER} -eq 1 ]; then
        create_config
    fi

    # Per-test setup steps.
}

function teardown() {
    # Global teardown; executed once per test file.
    if [[ "$BATS_TEST_NUMBER" -eq "${#BATS_TEST_NAMES[@]}" ]]; then
        delete_config
        rm -f "${RANDOM_FILE}"
    fi

    # Per-test teardown steps.
}

########## TESTS ##########

@test "Creating deployment ${DEPLOYMENT_NAME} from ${CONFIG}" {
    gcloud deployment-manager deployments create "${DEPLOYMENT_NAME}" \
        --config "${CONFIG}" --project "${CLOUD_FOUNDATION_PROJECT_ID}"
    [[ "$status" -eq 0 ]]
}

@test "Verify if Storage Bucket ${BUCKET_NAME} is created " {
    res=$(gsutil ls | grep "${BUCKET_NAME}")
    [[ "$status" -eq 0 ]]
    [[ "$res" =~ "gs://${BUCKET_NAME}/" ]]
}

@test "Verify if SAs have role ${ROLE}" {
    role=$(gsutil iam get "gs://${BUCKET_NAME}/" | grep role)
    [[ "$status" -eq 0 ]]
    [[ "$role" =~ "${ROLE}" ]]
}

@test "Verify if SAs are the members of this bucket" {
    run gsutil iam get "gs://${BUCKET_NAME}/" | grep serviceAccount:${TEST_SERVICE_ACCOUNT}-.*@${CLOUD_FOUNDATION_PROJECT_ID}.iam.gserviceaccount.com
    [[ "$status" -eq 0 ]]
}

@test "Deleting deployment ${DEPLOYMENT_NAME}" {
    gcloud deployment-manager deployments delete "${DEPLOYMENT_NAME}" \
        --project "${CLOUD_FOUNDATION_PROJECT_ID}" -q
    [[ "$status" -eq 0 ]]

    run gsutil ls
    [[ "$status" -eq 0 ]]
    [[ ! "$output" =~ "gs://${BUCKET_NAME}/" ]]
}
