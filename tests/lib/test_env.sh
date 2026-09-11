#!/bin/bash

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

azsmb_require_test_vm()
{
	local expected="${AZSMB_EXPECTED_HOSTNAME:-vmname}"
	local actual

	actual=$(hostname -s)
	if [[ "$actual" != "$expected" ]]; then
		printf 'E2E tests must run on %s, not %s\n' "$expected" "$actual" >&2
		return 1
	fi
}