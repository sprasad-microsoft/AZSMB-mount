#!/bin/bash

set -euo pipefail

AZSMB_REPO_ROOT="${AZSMB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AZSMB_RELEASE_VERSION="${AZSMB_RELEASE_VERSION:-0.1.0}"
AZSMB_ARTIFACT_DIR="${AZSMB_ARTIFACT_DIR:-$AZSMB_REPO_ROOT/out/container}"

rm -rf "$AZSMB_ARTIFACT_DIR"
mkdir -p "$AZSMB_ARTIFACT_DIR/deb" "$AZSMB_ARTIFACT_DIR/rpm"

docker build \
    --file "$AZSMB_REPO_ROOT/tests/containers/Dockerfile.build-deb" \
    --build-arg "AZSMB_RELEASE_VERSION=$AZSMB_RELEASE_VERSION" \
    --output "type=local,dest=$AZSMB_ARTIFACT_DIR/deb" \
    "$AZSMB_REPO_ROOT"

docker build \
    --file "$AZSMB_REPO_ROOT/tests/containers/Dockerfile.build-rpm" \
    --build-arg "AZSMB_RELEASE_VERSION=$AZSMB_RELEASE_VERSION" \
    --output "type=local,dest=$AZSMB_ARTIFACT_DIR/rpm" \
    "$AZSMB_REPO_ROOT"

find "$AZSMB_ARTIFACT_DIR" -maxdepth 2 -type f -print