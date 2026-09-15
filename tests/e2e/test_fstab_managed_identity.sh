#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$AZSMB_REPO_ROOT/tests/lib/test_env.sh"

azsmb_require_test_vm
azsmb_require_env AZURE_STORAGE_ACCOUNT AZURE_FILE_SHARE AZSMB_MI_CLIENT_ID

if (( EUID != 0 )); then
	printf 'fstab managed-identity test must run as root\n' >&2
	exit 1
fi

AZSMB_MOUNT_ROOT="${AZSMB_MOUNT_ROOT:-/mnt/azsmb-tests}"
AZSMB_TEST_RUN_ID="${AZSMB_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
MOUNT_POINT="$AZSMB_MOUNT_ROOT/fstab-$AZSMB_TEST_RUN_ID"
FSTAB_FILE="${AZSMB_FSTAB_FILE:-/etc/fstab}"
SOURCE="//$AZURE_STORAGE_ACCOUNT.file.core.windows.net/$AZURE_FILE_SHARE"
BACKUP_FILE=$(mktemp)

cleanup()
{
	if mountpoint -q "$MOUNT_POINT"; then
		rm -rf "${TEST_DIRECTORY:-}" 2>/dev/null || true
		umount "$MOUNT_POINT" || true
	fi
	if ! cp "$BACKUP_FILE" "$FSTAB_FILE"; then
		printf 'failed to restore %s\n' "$FSTAB_FILE" >&2
	fi
	systemctl daemon-reload || true
	rm -f "$BACKUP_FILE"
	rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

cp "$FSTAB_FILE" "$BACKUP_FILE"
mkdir -p "$MOUNT_POINT"
printf '%s %s azsmb _netdev,nofail,x-systemd.requires=azfilesrefresh.service,x-systemd.after=azfilesrefresh.service,client_id=%s 0 0\n' \
	"$SOURCE" "$MOUNT_POINT" "$AZSMB_MI_CLIENT_ID" >> "$FSTAB_FILE"
systemctl daemon-reload
mount "$MOUNT_POINT"
TEST_DIRECTORY="$MOUNT_POINT/.azsmb-fstab-test-$AZSMB_TEST_RUN_ID"
mkdir "$TEST_DIRECTORY"
printf '%s\n' "$AZSMB_TEST_RUN_ID" > "$TEST_DIRECTORY/payload"
[[ "$(cat "$TEST_DIRECTORY/payload")" == "$AZSMB_TEST_RUN_ID" ]]
systemctl is-active --quiet azfilesrefresh

printf 'PASS: fstab managed-identity mount test %s\n' "$AZSMB_TEST_RUN_ID"