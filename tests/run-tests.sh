#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export AZSMB_REPO_ROOT
. "$AZSMB_REPO_ROOT/tests/lib/test_env.sh"

azsmb_require_test_vm
bash "$AZSMB_REPO_ROOT/tests/run-unit-tests.sh"

if [[ "${AZSMB_RUN_KEY_E2E:-0}" == "1" ]]; then
	bash "$AZSMB_REPO_ROOT/tests/e2e/test_mounts.sh"
fi

if [[ "${AZSMB_RUN_SYSTEM_MI_E2E:-0}" == "1" ]]; then
	AZSMB_MI_CLIENT_ID=system \
		bash "$AZSMB_REPO_ROOT/tests/e2e/test_managed_identity.sh"
fi

if [[ "${AZSMB_RUN_USER_MI_E2E:-0}" == "1" ]]; then
	azsmb_require_env AZURE_USER_ASSIGNED_MI_CLIENT_ID
	AZSMB_MI_CLIENT_ID="$AZURE_USER_ASSIGNED_MI_CLIENT_ID" \
		bash "$AZSMB_REPO_ROOT/tests/e2e/test_managed_identity.sh"
fi