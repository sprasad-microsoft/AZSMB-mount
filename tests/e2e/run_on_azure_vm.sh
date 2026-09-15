#!/bin/bash

set -euo pipefail

azsmb_require_env()
{
	local name

	for name in "$@"; do
		if [[ -z "${!name:-}" ]]; then
			printf 'Required environment variable is not set: %s\n' "$name" >&2
			return 1
		fi
	done
}

azsmb_require_env AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP
AZURE_VM_NAME="${AZURE_VM_NAME:-vmname}"
AZSMB_REMOTE_REPO_PATH="${AZSMB_REMOTE_REPO_PATH:-/home/vmuser/repo/Azure/AZSMB-mount}"

remote_command=$(cat <<EOF
set -euo pipefail
cd '$AZSMB_REMOTE_REPO_PATH'
export AZSMB_REPO_ROOT='$AZSMB_REMOTE_REPO_PATH'
export AZURE_VM_NAME='$AZURE_VM_NAME'
export AZSMB_EXPECTED_HOSTNAME='${AZSMB_EXPECTED_HOSTNAME:-vmname}'
export AZURE_STORAGE_ACCOUNT='${AZURE_STORAGE_ACCOUNT:-}'
export AZURE_FILE_SHARE='${AZURE_FILE_SHARE:-}'
export AZSMB_CREDENTIAL_FILE='${AZSMB_CREDENTIAL_FILE:-}'
export AZSMB_TEST_REMOUNT='${AZSMB_TEST_REMOUNT:-0}'
export AZSMB_MI_CLIENT_ID='${AZSMB_MI_CLIENT_ID:-}'
export AZURE_USER_ASSIGNED_MI_CLIENT_ID='${AZURE_USER_ASSIGNED_MI_CLIENT_ID:-}'
export AZSMB_RUN_KEY_E2E='${AZSMB_RUN_KEY_E2E:-0}'
export AZSMB_RUN_SYSTEM_MI_E2E='${AZSMB_RUN_SYSTEM_MI_E2E:-0}'
export AZSMB_RUN_USER_MI_E2E='${AZSMB_RUN_USER_MI_E2E:-0}'
if [[ "\$AZSMB_RUN_KEY_E2E" == "1" && -z "\$AZSMB_CREDENTIAL_FILE" ]]; then
	echo 'AZSMB_CREDENTIAL_FILE must name an existing credential file on the VM; run key1/key2 tests directly on the VM' >&2
	exit 1
fi
sudo -E bash tests/run-tests.sh
EOF
)

az vm run-command invoke \
	--subscription "$AZURE_SUBSCRIPTION_ID" \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_VM_NAME" \
	--command-id RunShellScript \
	--scripts "$remote_command" \
	--query 'value[].message' -o tsv