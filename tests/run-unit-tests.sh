#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export AZSMB_REPO_ROOT

for test_script in "$AZSMB_REPO_ROOT"/tests/unit/test_*.sh; do
	bash "$test_script"
done