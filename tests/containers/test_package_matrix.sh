#!/bin/bash

set -euo pipefail

AZSMB_BUNDLE_ROOT="${AZSMB_BUNDLE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AZSMB_RESULT_DIR="${AZSMB_RESULT_DIR:-/tmp/azsmb-test-results}"
AZSMB_CONTAINER_TIMEOUT="${AZSMB_CONTAINER_TIMEOUT:-1200}"
AZSMB_TEST_DISTROS="${AZSMB_TEST_DISTROS:-ubuntu22 ubuntu24 azurelinux3 rhel96 sles15sp6}"
AZSMB_DOCKER_NO_CACHE="${AZSMB_DOCKER_NO_CACHE:-0}"
CONTEXT_DIR=$(mktemp -d)
trap 'rm -rf "$CONTEXT_DIR"' EXIT

rm -rf "$AZSMB_RESULT_DIR"
mkdir -p "$CONTEXT_DIR/artifacts" "$CONTEXT_DIR/source"
mkdir -p "$AZSMB_RESULT_DIR"
cp "${AZSMB_DEB_PACKAGE:?AZSMB_DEB_PACKAGE is required}" "$CONTEXT_DIR/artifacts/azsmb.deb"
cp "${AZSMB_RPM_PACKAGE:?AZSMB_RPM_PACKAGE is required}" "$CONTEXT_DIR/artifacts/azsmb.rpm"
cp -R "$AZSMB_BUNDLE_ROOT/lib" "$AZSMB_BUNDLE_ROOT/src" \
    "$AZSMB_BUNDLE_ROOT/tests" "$CONTEXT_DIR/source/"
cp "$AZSMB_BUNDLE_ROOT/tests/containers/"Dockerfile.test-* "$CONTEXT_DIR/"

run_build()
{
    local name="$1"
    shift
    local log="$AZSMB_RESULT_DIR/$name.log"
    local image="azsmb-test:$name"
    local -a cache_options=()

	if [[ "$AZSMB_DOCKER_NO_CACHE" == "1" ]]; then
		cache_options+=(--no-cache)
	fi

    printf 'RUNNING\n' > "$AZSMB_RESULT_DIR/$name.status"
    if timeout "$AZSMB_CONTAINER_TIMEOUT" \
        docker build "${cache_options[@]}" "$@" > "$log" 2>&1; then
        printf 'PASS\n' > "$AZSMB_RESULT_DIR/$name.status"
        printf 'PASS: %s\n' "$name"
        docker image rm --force "$image" >/dev/null 2>&1 || true
        docker image prune --force >/dev/null 2>&1 || true
    else
        printf 'FAIL\n' > "$AZSMB_RESULT_DIR/$name.status"
        tail -n 80 "$log" >&2
        return 1
    fi
}

for distro in $AZSMB_TEST_DISTROS; do
    case "$distro" in
        ubuntu22)
            run_build ubuntu22 \
                --file "$CONTEXT_DIR/Dockerfile.test-ubuntu" \
                --build-arg BASE_IMAGE=ubuntu:22.04 \
                --build-arg UBUNTU_VERSION=22.04 \
                --tag azsmb-test:ubuntu22 "$CONTEXT_DIR"
            ;;
        ubuntu24)
            run_build ubuntu24 \
                --file "$CONTEXT_DIR/Dockerfile.test-ubuntu" \
                --build-arg BASE_IMAGE=ubuntu:24.04 \
                --build-arg UBUNTU_VERSION=24.04 \
                --tag azsmb-test:ubuntu24 "$CONTEXT_DIR"
            ;;
        azurelinux3)
            run_build azurelinux3 \
                --file "$CONTEXT_DIR/Dockerfile.test-azurelinux" \
                --tag azsmb-test:azurelinux3 "$CONTEXT_DIR"
            ;;
        rhel96)
            run_build rhel96 \
                --file "$CONTEXT_DIR/Dockerfile.test-rhel" \
                --tag azsmb-test:rhel96 "$CONTEXT_DIR"
            ;;
        sles15sp6)
            run_build sles15sp6 \
                --file "$CONTEXT_DIR/Dockerfile.test-sles" \
                --tag azsmb-test:sles15sp6 "$CONTEXT_DIR"
            ;;
        *)
            printf 'Unknown distro target: %s\n' "$distro" >&2
            exit 1
            ;;
    esac
done

printf 'PASS: package validation completed for all distro containers\n'