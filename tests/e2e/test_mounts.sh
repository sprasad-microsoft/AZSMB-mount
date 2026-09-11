#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$AZSMB_REPO_ROOT/tests/lib/test_env.sh"

azsmb_require_test_vm
azsmb_require_env AZURE_STORAGE_ACCOUNT AZURE_FILE_SHARE AZSMB_CREDENTIAL_FILE

AZSMB_MOUNT_ROOT="${AZSMB_MOUNT_ROOT:-/mnt/azsmb-tests}"
AZSMB_TEST_RUN_ID="${AZSMB_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
MOUNT_POINT="$AZSMB_MOUNT_ROOT/key-$AZSMB_TEST_RUN_ID"
SOURCE="//$AZURE_STORAGE_ACCOUNT.file.core.windows.net/$AZURE_FILE_SHARE"

cleanup()
{
	if mountpoint -q "$MOUNT_POINT"; then
		rm -rf "${TEST_DIRECTORY:-}" 2>/dev/null || true
		umount "$MOUNT_POINT" || true
	fi
	rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

if [[ ! -r "$AZSMB_CREDENTIAL_FILE" ]]; then
	printf 'Credential file is not readable: %s\n' "$AZSMB_CREDENTIAL_FILE" >&2
	exit 1
fi
mkdir -p "$MOUNT_POINT"

mount -t azsmb "$SOURCE" "$MOUNT_POINT" -o "credentials=$AZSMB_CREDENTIAL_FILE"
TEST_DIRECTORY="$MOUNT_POINT/.azsmb-test-$AZSMB_TEST_RUN_ID"
mkdir "$TEST_DIRECTORY"
printf '%s\n' "$AZSMB_TEST_RUN_ID" > "$TEST_DIRECTORY/payload"
[[ "$(cat "$TEST_DIRECTORY/payload")" == "$AZSMB_TEST_RUN_ID" ]]
rm -rf "$TEST_DIRECTORY"

printf 'PASS: storage-key mount test %s\n' "$AZSMB_TEST_RUN_ID"