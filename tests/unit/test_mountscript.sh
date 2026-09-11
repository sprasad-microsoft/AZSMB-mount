#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

. "$AZSMB_REPO_ROOT/src/mountscript.sh"

tests_run=0

fail()
{
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_succeeds()
{
	local description="$1"
	shift

	"$@" || fail "$description"
	tests_run=$((tests_run + 1))
}

assert_fails()
{
	local description="$1"
	shift

	if "$@" >/dev/null 2>&1; then
		fail "$description"
	fi
	tests_run=$((tests_run + 1))
}

assert_contains()
{
	local value="$1"
	local expected="$2"
	local description="$3"

	[[ "$value" == *"$expected"* ]] || fail "$description: '$expected' not found in '$value'"
	tests_run=$((tests_run + 1))
}

assert_not_contains()
{
	local value="$1"
	local unexpected="$2"
	local description="$3"

	[[ "$value" != *"$unexpected"* ]] || fail "$description: '$unexpected' found in '$value'"
	tests_run=$((tests_run + 1))
}

set_os_release()
{
	AZSMB_OS_RELEASE_FILE="$TEST_TMPDIR/os-release"
	AZSMB_AUTH_CONFIG_FILE="$TEST_TMPDIR/config.yaml"
	export AZSMB_OS_RELEASE_FILE AZSMB_AUTH_CONFIG_FILE
	printf 'ID=%s\nVERSION_ID="%s"\n' "$1" "$2" > "$AZSMB_OS_RELEASE_FILE"
	printf 'USER_UID: 1234\n' > "$AZSMB_AUTH_CONFIG_FILE"
}

test_source_validation()
{
	assert_succeeds "public endpoint" azsmb_validate_source "//account.file.core.windows.net/share"
	assert_succeeds "private endpoint" azsmb_validate_source "//account.privatelink.file.core.windows.net/share"
	assert_succeeds "government endpoint" azsmb_validate_source "//account.file.core.usgovcloudapi.net/share"
	assert_fails "non-Azure endpoint" azsmb_validate_source "//server.example.com/share"
	assert_fails "nested path" azsmb_validate_source "//account.file.core.windows.net/share/path"
}

test_auth_conflicts()
{
	assert_succeeds "regular credential mount" azsmb_validate_auth_options "credentials=/tmp/account.cred"
	assert_succeeds "system MI" azsmb_validate_auth_options "client_id=system"
	assert_succeeds "user MI" azsmb_validate_auth_options "client_id=00000000-0000-0000-0000-000000000001"
	assert_fails "MI with credential file" azsmb_validate_auth_options "client_id=system,credentials=/tmp/account.cred"
	assert_fails "MI with password" azsmb_validate_auth_options "client_id=system,password=secret"
	assert_fails "invalid client ID" azsmb_validate_auth_options "client_id=not-a-client-id"
}

test_mi_option_translation()
{
	local actual
	local command_log="$TEST_TMPDIR/commands"

	set_os_release ubuntu 24.04
	azfilesauthmanager()
	{
		printf 'azfilesauthmanager %s\n' "$*" >> "$command_log"
		printf 'credential setup status that must not become a mount option\n'
	}
	systemctl()
	{
		printf 'systemctl %s\n' "$*" >> "$command_log"
		return 0
	}

	actual=$(azsmb_prepare_managed_identity \
		"//account.file.core.windows.net/share" \
		"client_id=system")
	assert_not_contains "$actual" "client_id=" "system MI helper option removed"
	assert_contains "$actual" "sec=krb5" "system MI security option"
	assert_contains "$actual" "cruid=1234" "system MI credential UID"
	assert_not_contains "$actual" "username=" "system MI has no username"
	assert_not_contains "$actual" "credential setup status" "credential setup output suppressed"

	actual=$(azsmb_prepare_managed_identity \
		"//account.file.core.windows.net/share" \
		"client_id=00000000-0000-0000-0000-000000000001")
	assert_contains "$actual" "username=00000000-0000-0000-0000-000000000001" "user MI username"
	assert_contains "$(cat "$command_log")" "--system" "system MI credential preparation"
	assert_contains "$(cat "$command_log")" "--imds-client-id 00000000-0000-0000-0000-000000000001" "user MI credential preparation"
	assert_fails "MI rejects non-Kerberos security" azsmb_prepare_managed_identity \
		"//account.file.core.windows.net/share" "client_id=system,sec=ntlmssp"
}

test_mi_distro_gate()
{
	set_os_release debian 12
	assert_fails "unsupported system MI distro" azsmb_prepare_managed_identity \
		"//account.file.core.windows.net/share" "client_id=system"
	assert_fails "unsupported user MI distro" azsmb_prepare_managed_identity \
		"//account.file.core.windows.net/share" \
		"client_id=00000000-0000-0000-0000-000000000001"
}

test_controlled_options()
{
	assert_fails "conflicting max_channels" azsmb_add_default_options "max_channels=2"
	assert_fails "conflicting rasize" azsmb_add_default_options "rasize=1048576"
}

test_mount_delegation()
{
	local fake_bin="$TEST_TMPDIR/bin"
	local mount_log="$TEST_TMPDIR/mount-command"
	local output

	mkdir -p "$fake_bin"
	cat > "$fake_bin/mount" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$AZSMB_MOUNT_LOG"
EOF
	chmod 0755 "$fake_bin/mount"
	set_os_release debian 12
	AZSMB_KERNEL_RELEASE=6.3.0
	AZSMB_MOUNT_LOG="$mount_log"
	export AZSMB_KERNEL_RELEASE AZSMB_MOUNT_LOG

	PATH="$fake_bin:$PATH" bash "$AZSMB_REPO_ROOT/src/mountscript.sh" \
		"//account.file.core.windows.net/share" /mnt/test \
		-o credentials=/tmp/account.cred
	output=$(tr '\n' ' ' < "$mount_log")
	assert_contains "$output" "-t cifs" "delegates through mount -t cifs"
	assert_contains "$output" "credentials=/tmp/account.cred,nosharesock,actimeo=30,mfsymlinks" "adds regular mount defaults"
	assert_not_contains "$output" "vers=" "does not inject vers"
	assert_not_contains "$output" "serverino" "does not inject serverino"
}

test_source_validation
test_auth_conflicts
test_mi_option_translation
test_mi_distro_gate
test_controlled_options
test_mount_delegation

printf 'PASS: %d assertions\n' "$tests_run"