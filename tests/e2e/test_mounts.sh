#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$AZSMB_REPO_ROOT/tests/lib/test_env.sh"

azsmb_require_test_vm
azsmb_require_env AZURE_STORAGE_ACCOUNT AZURE_FILE_SHARE

if [[ -z "${AZSMB_KEY1:-}" && -z "${AZSMB_CREDENTIAL_FILE:-}" ]]; then
	printf 'AZSMB_KEY1 or AZSMB_CREDENTIAL_FILE is required\n' >&2
	exit 1
fi

AZSMB_MOUNT_ROOT="${AZSMB_MOUNT_ROOT:-/mnt/azsmb-tests}"
AZSMB_TEST_RUN_ID="${AZSMB_TEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
MOUNT_POINT="$AZSMB_MOUNT_ROOT/key-$AZSMB_TEST_RUN_ID"
SOURCE="//$AZURE_STORAGE_ACCOUNT.file.core.windows.net/$AZURE_FILE_SHARE"
GENERATED_CREDENTIAL_FILE="/etc/smbcredentials/$AZURE_STORAGE_ACCOUNT.cred"

cleanup()
{
	if mountpoint -q "$MOUNT_POINT"; then
		rm -rf "${TEST_DIRECTORY:-}" 2>/dev/null || true
		umount "$MOUNT_POINT" || true
	fi
	if [[ -n "${AZSMB_KEY1:-}" ]]; then
		rm -f "$GENERATED_CREDENTIAL_FILE"
	fi
	rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$MOUNT_POINT"

if [[ -n "${AZSMB_KEY1:-}" ]]; then
	mount_options="key1=$AZSMB_KEY1"
	if [[ -n "${AZSMB_KEY2:-}" ]]; then
		mount_options+=",key2=$AZSMB_KEY2"
	fi
	mount -t azsmb "$SOURCE" "$MOUNT_POINT" -o "$mount_options"
	test -r "$GENERATED_CREDENTIAL_FILE"
	test "$(stat -c '%a' "$GENERATED_CREDENTIAL_FILE")" = "600"
	grep -Fxq "username=$AZURE_STORAGE_ACCOUNT" "$GENERATED_CREDENTIAL_FILE"
	grep -Fxq "password=$AZSMB_KEY1" "$GENERATED_CREDENTIAL_FILE"
	if [[ -n "${AZSMB_KEY2:-}" ]]; then
		grep -Fxq "password2=$AZSMB_KEY2" "$GENERATED_CREDENTIAL_FILE"
	fi
	if [[ "${AZSMB_TEST_REMOUNT:-0}" == "1" ]]; then
		if [[ -z "${AZSMB_KEY2:-}" ]]; then
			printf 'AZSMB_KEY2 is required for a dual-key remount test\n' >&2
			exit 1
		fi
		remount_key1="${AZSMB_REMOUNT_KEY1:-$AZSMB_KEY1}"
		remount_key2="${AZSMB_REMOUNT_KEY2:-$AZSMB_KEY2}"
		key1_changed=0
		key2_changed=0
		[[ "$remount_key1" == "$AZSMB_KEY1" ]] || key1_changed=1
		[[ "$remount_key2" == "$AZSMB_KEY2" ]] || key2_changed=1
		if (( key1_changed + key2_changed != 1 )); then
			printf 'Exactly one remount key must differ from its initial value\n' >&2
			exit 1
		fi
		if (( key1_changed )); then
			unchanged_key="$remount_key2"
			changed_key="$remount_key1"
		else
			unchanged_key="$remount_key1"
			changed_key="$remount_key2"
		fi
		mount -t azsmb "$SOURCE" "$MOUNT_POINT" \
			-o "remount,key1=$remount_key1,key2=$remount_key2"
		grep -Fxq "password=$unchanged_key" "$GENERATED_CREDENTIAL_FILE"
		grep -Fxq "password2=$changed_key" "$GENERATED_CREDENTIAL_FILE"
	fi
else
	if [[ ! -r "$AZSMB_CREDENTIAL_FILE" ]]; then
		printf 'Credential file is not readable: %s\n' "$AZSMB_CREDENTIAL_FILE" >&2
		exit 1
	fi
	mount -t azsmb "$SOURCE" "$MOUNT_POINT" -o "credentials=$AZSMB_CREDENTIAL_FILE"
fi
TEST_DIRECTORY="$MOUNT_POINT/.azsmb-test-$AZSMB_TEST_RUN_ID"
mkdir "$TEST_DIRECTORY"
printf '%s\n' "$AZSMB_TEST_RUN_ID" > "$TEST_DIRECTORY/payload"
[[ "$(cat "$TEST_DIRECTORY/payload")" == "$AZSMB_TEST_RUN_ID" ]]
rm -rf "$TEST_DIRECTORY"

printf 'PASS: storage-key mount test %s\n' "$AZSMB_TEST_RUN_ID"