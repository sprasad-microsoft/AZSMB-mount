#!/bin/bash

set -euo pipefail

STATE_FILE="${AZSMB_AZURE_STATE_FILE:?AZSMB_AZURE_STATE_FILE is required}"
if [[ ! -r "$STATE_FILE" ]]; then
	printf 'State file is not readable: %s\n' "$STATE_FILE" >&2
	exit 1
fi
. "$STATE_FILE"

if [[ "${AZSMB_KEEP_TEST_RESOURCES:-0}" == "1" ]]; then
	printf 'Retaining test-created Azure resources for run %s\n' "$AZSMB_TEST_RUN_ID"
	exit 0
fi

storage_lock_file=$(mktemp)
storage_locks_removed=0
restore_storage_locks()
{
	if [[ "$storage_locks_removed" == "1" && -s "$storage_lock_file" ]]; then
		while IFS=$'\t' read -r name level notes; do
			az lock create \
				--subscription "$AZURE_SUBSCRIPTION_ID" \
				--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
				--resource-type Microsoft.Storage/storageAccounts \
				--resource-name "$AZURE_STORAGE_ACCOUNT" \
				--name "$name" \
				--lock-type "$level" \
				--notes "$notes" >/dev/null
		done < "$storage_lock_file"
	fi
	rm -f "$storage_lock_file"
}
trap restore_storage_locks EXIT

az lock list \
	--subscription "$AZURE_SUBSCRIPTION_ID" \
	--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
	--resource-type Microsoft.Storage/storageAccounts \
	--resource-name "$AZURE_STORAGE_ACCOUNT" \
	--query '[].join(`\t`, [name, level, notes])' -o tsv > "$storage_lock_file"

if [[ -s "$storage_lock_file" && \
	( -n "${AZSMB_CREATED_ROLE_ASSIGNMENTS:-}" || \
	"${AZSMB_CHANGED_SMB_OAUTH:-0}" == "1" ) ]]; then
	while IFS=$'\t' read -r name _; do
		az lock delete \
			--subscription "$AZURE_SUBSCRIPTION_ID" \
			--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
			--resource-type Microsoft.Storage/storageAccounts \
			--resource-name "$AZURE_STORAGE_ACCOUNT" \
			--name "$name"
	done < "$storage_lock_file"
	storage_locks_removed=1
fi

IFS=',' read -r -a role_assignments <<< "${AZSMB_CREATED_ROLE_ASSIGNMENTS:-}"
for assignment_id in "${role_assignments[@]}"; do
	if [[ -n "$assignment_id" ]]; then
		az role assignment delete --ids "$assignment_id"
	fi
done

if [[ "${AZSMB_ATTACHED_USER_IDENTITY:-0}" == "1" ]]; then
	az vm identity remove \
		--subscription "$AZURE_SUBSCRIPTION_ID" \
		--resource-group "$AZURE_RESOURCE_GROUP" \
		--name "$AZURE_VM_NAME" \
		--identities "$AZSMB_USER_IDENTITY_RESOURCE_ID"
fi

if [[ "${AZSMB_CREATED_USER_IDENTITY:-0}" == "1" ]]; then
	tag=$(az identity show \
		--subscription "$AZURE_SUBSCRIPTION_ID" \
		--resource-group "$AZURE_RESOURCE_GROUP" \
		--name "$AZURE_USER_ASSIGNED_MI_NAME" \
		--query 'tags."azsmb-test-run"' -o tsv 2>/dev/null || true)
	if [[ "$tag" == "$AZSMB_TEST_RUN_ID" ]]; then
		az identity delete \
			--subscription "$AZURE_SUBSCRIPTION_ID" \
			--resource-group "$AZURE_RESOURCE_GROUP" \
			--name "$AZURE_USER_ASSIGNED_MI_NAME"
	fi
fi

if [[ "${AZSMB_CREATED_SYSTEM_IDENTITY:-0}" == "1" ]]; then
	az vm identity remove \
		--subscription "$AZURE_SUBSCRIPTION_ID" \
		--resource-group "$AZURE_RESOURCE_GROUP" \
		--name "$AZURE_VM_NAME" \
		--identities '[system]'
fi

if [[ "${AZSMB_CHANGED_SMB_OAUTH:-0}" == "1" ]]; then
	az storage account update \
		--subscription "$AZURE_SUBSCRIPTION_ID" \
		--resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
		--name "$AZURE_STORAGE_ACCOUNT" \
		--enable-smb-oauth false >/dev/null
fi

rm -f "$STATE_FILE"
restore_storage_locks
storage_locks_removed=0
trap - EXIT