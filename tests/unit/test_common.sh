#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

. "$AZSMB_REPO_ROOT/lib/common.sh"

tests_run=0

fail()
{
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_true()
{
	local description="$1"
	shift

	"$@" || fail "$description"
	tests_run=$((tests_run + 1))
}

assert_false()
{
	local description="$1"
	shift

	if "$@"; then
		fail "$description"
	fi
	tests_run=$((tests_run + 1))
}

assert_equal()
{
	local expected="$1"
	local actual="$2"
	local description="$3"

	[[ "$actual" == "$expected" ]] || fail "$description: expected '$expected', got '$actual'"
	tests_run=$((tests_run + 1))
}

set_os_release()
{
	local distro="$1"
	local version="$2"

	AZSMB_OS_RELEASE_FILE="$TEST_TMPDIR/os-release"
	export AZSMB_OS_RELEASE_FILE
	printf 'ID=%s\nVERSION_ID="%s"\n' "$distro" "$version" > "$AZSMB_OS_RELEASE_FILE"
}

test_mi_distro_matrix()
{
	local test_case
	local distro
	local version
	local expected

	for test_case in \
		"azurelinux 3.0 yes" \
		"ubuntu 22.04 yes" \
		"ubuntu 24.04 yes" \
		"rhel 9.5 no" \
		"rhel 9.6 yes" \
		"sles 15.5 no" \
		"sles 15.6 yes" \
		"sles 15-SP6 yes" \
		"debian 12 no"; do
		read -r distro version expected <<< "$test_case"
		set_os_release "$distro" "$version"
		if [[ "$expected" == "yes" ]]; then
			assert_true "MI support for $distro $version" azsmb_mi_distro_supported
		else
			assert_false "MI rejection for $distro $version" azsmb_mi_distro_supported
		fi
	done
}

test_multichannel_thresholds()
{
	set_os_release ubuntu 24.04
	AZSMB_ENVIRONMENT=aks AZSMB_KERNEL_RELEASE=6.8.0-1041
	export AZSMB_ENVIRONMENT AZSMB_KERNEL_RELEASE
	assert_false "Ubuntu 24.04 AKS below threshold" azsmb_multichannel_supported
	AZSMB_KERNEL_RELEASE=6.8.0-1042
	assert_true "Ubuntu 24.04 AKS at threshold" azsmb_multichannel_supported

	AZSMB_ENVIRONMENT=vm AZSMB_KERNEL_RELEASE=6.14.0-1016
	assert_false "Ubuntu 24.04 VM below threshold" azsmb_multichannel_supported
	AZSMB_KERNEL_RELEASE=6.14.0-1017
	assert_true "Ubuntu 24.04 VM at threshold" azsmb_multichannel_supported

	set_os_release ubuntu 22.04
	AZSMB_KERNEL_RELEASE=6.8.0-1044
	assert_true "Ubuntu 22.04 VM at threshold" azsmb_multichannel_supported

	set_os_release azurelinux 3.0
	AZSMB_KERNEL_RELEASE=6.6.106.1
	assert_true "Azure Linux at threshold" azsmb_multichannel_supported

	set_os_release rhel 9.7
	AZSMB_KERNEL_RELEASE=5.14.0-611.5.1.el9_7
	assert_true "RHEL 9.7 at threshold" azsmb_multichannel_supported

	set_os_release sles 15.6
	AZSMB_KERNEL_RELEASE=6.12.0
	assert_false "SLES without documented threshold" azsmb_multichannel_supported
}

test_rasize_threshold()
{
	AZSMB_KERNEL_RELEASE=6.3.99
	export AZSMB_KERNEL_RELEASE
	assert_false "rasize below kernel 6.4" azsmb_rasize_supported
	AZSMB_KERNEL_RELEASE=6.4.0-azure
	assert_true "rasize at kernel 6.4" azsmb_rasize_supported
	AZSMB_KERNEL_RELEASE=7.0.0
	assert_true "rasize above kernel 6.4" azsmb_rasize_supported
}

test_password2_threshold()
{
	AZSMB_KERNEL_RELEASE=6.8.99
	export AZSMB_KERNEL_RELEASE
	assert_false "password2 below kernel 6.9" azsmb_password2_supported
	AZSMB_KERNEL_RELEASE=6.9.0-azure
	assert_true "password2 at kernel 6.9" azsmb_password2_supported
	AZSMB_KERNEL_RELEASE=7.0.0
	assert_true "password2 above kernel 6.9" azsmb_password2_supported
}

test_cifs_utils_threshold()
{
	AZSMB_CIFS_UTILS_VERSION=7.1
	export AZSMB_CIFS_UTILS_VERSION
	assert_false "dual-key remount below cifs-utils 7.2" azsmb_dual_key_remount_supported
	AZSMB_CIFS_UTILS_VERSION=7.2
	assert_true "dual-key remount at cifs-utils 7.2" azsmb_dual_key_remount_supported
	AZSMB_CIFS_UTILS_VERSION=7.7
	assert_true "dual-key remount above cifs-utils 7.2" azsmb_dual_key_remount_supported
}

test_default_options()
{
	local actual

	set_os_release ubuntu 24.04
	AZSMB_ENVIRONMENT=vm AZSMB_KERNEL_RELEASE=6.14.0-1017
	export AZSMB_ENVIRONMENT AZSMB_KERNEL_RELEASE
	actual=$(azsmb_add_default_options "credentials=/tmp/test.cred,actimeo=45")
	assert_equal \
		"credentials=/tmp/test.cred,actimeo=45,nosharesock,mfsymlinks,max_channels=4,rasize=8388608" \
		"$actual" \
		"default option merge"
	assert_false "vers must not be injected" azsmb_option_present "$actual" vers
	assert_false "serverino must not be injected" azsmb_option_present "$actual" serverino
}

test_mi_distro_matrix
test_multichannel_thresholds
test_rasize_threshold
test_password2_threshold
test_cifs_utils_threshold
test_default_options

printf 'PASS: %d assertions\n' "$tests_run"