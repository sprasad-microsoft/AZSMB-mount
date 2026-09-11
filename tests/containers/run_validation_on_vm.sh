#!/bin/bash

set -euo pipefail

AZSMB_BUNDLE_ROOT="${AZSMB_BUNDLE_ROOT:-/tmp/azsmb-validation}"
AZSMB_DEB_PACKAGE="${AZSMB_DEB_PACKAGE:-$AZSMB_BUNDLE_ROOT/out/container/deb/azsmb_0.1.0_amd64.deb}"
AZSMB_RPM_PACKAGE="${AZSMB_RPM_PACKAGE:-$AZSMB_BUNDLE_ROOT/out/container/rpm/azsmb-0.1.0-1.x86_64.rpm}"
AZSMB_RESULT_DIR="${AZSMB_RESULT_DIR:-/tmp/azsmb-test-results}"

if [[ "$(hostname -s)" != "vmname" ]]; then
	printf 'Container validation must run on vmname\n' >&2
	exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
	printf 'Docker is required on the Azure test VM\n' >&2
	exit 1
fi

export AZSMB_BUNDLE_ROOT AZSMB_DEB_PACKAGE AZSMB_RPM_PACKAGE AZSMB_RESULT_DIR
bash "$AZSMB_BUNDLE_ROOT/tests/containers/test_package_matrix.sh"