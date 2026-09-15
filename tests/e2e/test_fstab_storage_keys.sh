#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$AZSMB_REPO_ROOT/tests/lib/test_env.sh"

azsmb_require_test_vm
azsmb_require_env AZURE_STORAGE_ACCOUNT AZURE_FILE_SHARE AZSMB_KEY1 AZSMB_KEY2

if (( EUID != 0 )); then
	printf 'fstab storage-key test must run as root\n' >&2
	exit 1
fi

AZSMB_MOUNT_ROOT="${AZSMB_MOUNT_ROOT:-/mnt/azsmb-tests}"
AZSMB_TEST_RUN_ID="${AZSMB_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
MOUNT_POINT="$AZSMB_MOUNT_ROOT/fstab-key-$AZSMB_TEST_RUN_ID"
FSTAB_FILE="${AZSMB_FSTAB_FILE:-/etc/fstab}"
SOURCE="//$AZURE_STORAGE_ACCOUNT.file.core.windows.net/$AZURE_FILE_SHARE"
GENERATED_CREDENTIAL_FILE="/etc/smbcredentials/$AZURE_STORAGE_ACCOUNT.cred"
BACKUP_FILE=$(mktemp)
CREDENTIAL_BACKUP=$(mktemp)
CREDENTIAL_EXISTED=0
TEST_DIRECTORY="$MOUNT_POINT/.azsmb-fstab-key-test-$AZSMB_TEST_RUN_ID"

cleanup()
{
	if mountpoint -q "$MOUNT_POINT"; then
		rm -rf "$TEST_DIRECTORY" 2>/dev/null || true
		umount "$MOUNT_POINT" || true
	fi
	if ! cp "$BACKUP_FILE" "$FSTAB_FILE"; then
		printf 'failed to restore %s\n' "$FSTAB_FILE" >&2
	fi
	systemctl daemon-reload || true
	if (( CREDENTIAL_EXISTED )); then
		cp "$CREDENTIAL_BACKUP" "$GENERATED_CREDENTIAL_FILE"
	else
		rm -f "$GENERATED_CREDENTIAL_FILE"
	fi
	rm -f "$CREDENTIAL_BACKUP" "$BACKUP_FILE"
	rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

cp "$FSTAB_FILE" "$BACKUP_FILE"
if [[ -e "$GENERATED_CREDENTIAL_FILE" ]]; then
	cp "$GENERATED_CREDENTIAL_FILE" "$CREDENTIAL_BACKUP"
	CREDENTIAL_EXISTED=1
fi
mkdir -p "$MOUNT_POINT"
printf '%s %s azsmb _netdev,nofail,key1=%s,key2=%s 0 0\n' \
	"$SOURCE" "$MOUNT_POINT" "$AZSMB_KEY1" "$AZSMB_KEY2" >> "$FSTAB_FILE"
systemctl daemon-reload
mount "$MOUNT_POINT"
grep -Fxq "username=$AZURE_STORAGE_ACCOUNT" "$GENERATED_CREDENTIAL_FILE"
grep -Fxq "password=$AZSMB_KEY1" "$GENERATED_CREDENTIAL_FILE"
grep -Fxq "password2=$AZSMB_KEY2" "$GENERATED_CREDENTIAL_FILE"
test "$(stat -c '%a' "$GENERATED_CREDENTIAL_FILE")" = 600
mkdir "$TEST_DIRECTORY"
printf '%s\n' "$AZSMB_TEST_RUN_ID" > "$TEST_DIRECTORY/payload"
[[ "$(cat "$TEST_DIRECTORY/payload")" == "$AZSMB_TEST_RUN_ID" ]]

printf 'PASS: fstab storage-key mount test %s\n' "$AZSMB_TEST_RUN_ID"