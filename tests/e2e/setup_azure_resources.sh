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

azsmb_require_env AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP AZURE_STORAGE_ACCOUNT
AZURE_VM_NAME="${AZURE_VM_NAME:-vmname}"
AZURE_STORAGE_RESOURCE_GROUP="${AZURE_STORAGE_RESOURCE_GROUP:-$AZURE_RESOURCE_GROUP}"
AZSMB_TEST_RUN_ID="${AZSMB_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
AZURE_USER_ASSIGNED_MI_NAME="${AZURE_USER_ASSIGNED_MI_NAME:-azsmb-test-$AZSMB_TEST_RUN_ID}"
STATE_FILE="${AZSMB_AZURE_STATE_FILE:-/tmp/azsmb-azure-$AZSMB_TEST_RUN_ID.env}"

az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az vm show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_VM_NAME" >/dev/null
az storage account show \
	--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
	--name "$AZURE_STORAGE_ACCOUNT" >/dev/null

existing_system_principal=$(az vm show \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_VM_NAME" \
	--query identity.principalId -o tsv)
system_principal=$(az vm identity assign \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_VM_NAME" \
	--query systemAssignedIdentity -o tsv)
if [[ -z "$existing_system_principal" ]]; then
	created_system_identity=1
else
	created_system_identity=0
fi

if az identity show \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_USER_ASSIGNED_MI_NAME" >/dev/null 2>&1; then
	created_user_identity=0
else
	az identity create \
		--resource-group "$AZURE_RESOURCE_GROUP" \
		--name "$AZURE_USER_ASSIGNED_MI_NAME" \
		--tags azsmb-test-run="$AZSMB_TEST_RUN_ID" >/dev/null
	created_user_identity=1
fi

user_identity_id=$(az identity show \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_USER_ASSIGNED_MI_NAME" \
	--query id -o tsv)
user_client_id=$(az identity show \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_USER_ASSIGNED_MI_NAME" \
	--query clientId -o tsv)
user_principal_id=$(az identity show \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_USER_ASSIGNED_MI_NAME" \
	--query principalId -o tsv)

if az vm show \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_VM_NAME" \
	--query "identity.userAssignedIdentities | keys(@)" -o tsv | \
	grep -Fxq "$user_identity_id"; then
	attached_user_identity=0
else
	attached_user_identity=1
fi
az vm identity assign \
	--resource-group "$AZURE_RESOURCE_GROUP" \
	--name "$AZURE_VM_NAME" \
	--identities "$user_identity_id" >/dev/null
existing_smb_oauth=$(az storage account show \
	--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
	--name "$AZURE_STORAGE_ACCOUNT" \
	--query enableSmbOAuth -o tsv)
changed_smb_oauth=0
if [[ "$existing_smb_oauth" != "true" ]]; then
	az storage account update \
		--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
		--name "$AZURE_STORAGE_ACCOUNT" \
		--enable-smb-oauth true >/dev/null
	changed_smb_oauth=1
fi

storage_id=$(az storage account show \
	--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
	--name "$AZURE_STORAGE_ACCOUNT" \
	--query id -o tsv)
role_name="Storage File Data SMB MI Admin"
created_role_assignments=""

for principal_id in "$system_principal" "$user_principal_id"; do
	if az role assignment list \
		--assignee-object-id "$principal_id" \
		--scope "$storage_id" \
		--role "$role_name" \
		--query '[0].id' -o tsv | grep -q .; then
		continue
	fi
	assignment_id=$(az role assignment create \
		--assignee-object-id "$principal_id" \
		--assignee-principal-type ServicePrincipal \
		--role "$role_name" \
		--scope "$storage_id" \
		--query id -o tsv)
	created_role_assignments="${created_role_assignments}${created_role_assignments:+,}${assignment_id}"
done

umask 077
cat > "$STATE_FILE" <<EOF
AZSMB_TEST_RUN_ID=$AZSMB_TEST_RUN_ID
AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
AZURE_RESOURCE_GROUP=$AZURE_RESOURCE_GROUP
AZURE_VM_NAME=$AZURE_VM_NAME
AZURE_STORAGE_ACCOUNT=$AZURE_STORAGE_ACCOUNT
AZURE_STORAGE_RESOURCE_GROUP=$AZURE_STORAGE_RESOURCE_GROUP
AZURE_USER_ASSIGNED_MI_NAME=$AZURE_USER_ASSIGNED_MI_NAME
AZURE_USER_ASSIGNED_MI_CLIENT_ID=$user_client_id
AZSMB_CREATED_USER_IDENTITY=$created_user_identity
AZSMB_ATTACHED_USER_IDENTITY=$attached_user_identity
AZSMB_CREATED_SYSTEM_IDENTITY=$created_system_identity
AZSMB_CHANGED_SMB_OAUTH=$changed_smb_oauth
AZSMB_CREATED_ROLE_ASSIGNMENTS=$created_role_assignments
AZSMB_USER_IDENTITY_RESOURCE_ID=$user_identity_id
EOF

printf '%s\n' "$STATE_FILE"