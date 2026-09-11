#!/bin/bash

set -euo pipefail

SOURCE_DIR="${AZSMB_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
OUTPUT_DIR="${AZSMB_OUTPUT_DIR:-$SOURCE_DIR/out}"
AZSMB_RELEASE_VERSION="${AZSMB_RELEASE_VERSION:?AZSMB_RELEASE_VERSION is required}"
AZSMB_PACKAGE_FORMAT="${AZSMB_PACKAGE_FORMAT:-all}"

if [[ "$AZSMB_PACKAGE_FORMAT" != "all" && \
	"$AZSMB_PACKAGE_FORMAT" != "deb" && \
	"$AZSMB_PACKAGE_FORMAT" != "rpm" ]]; then
	printf 'Unsupported package format: %s\n' "$AZSMB_PACKAGE_FORMAT" >&2
	exit 1
fi

case "$(uname -m)" in
	x86_64)
		DEB_ARCH=amd64
		RPM_ARCH=x86_64
		;;
	aarch64)
		DEB_ARCH=arm64
		RPM_ARCH=aarch64
		;;
	*)
		printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
		exit 1
		;;
esac

rm -rf "$OUTPUT_DIR/staging"
mkdir -p "$OUTPUT_DIR/staging"

if [[ "$AZSMB_PACKAGE_FORMAT" == "all" || "$AZSMB_PACKAGE_FORMAT" == "deb" ]]; then
	mkdir -p "$OUTPUT_DIR/staging/deb/DEBIAN"
	mkdir -p "$OUTPUT_DIR/staging/deb/sbin"
	mkdir -p "$OUTPUT_DIR/staging/deb/opt/microsoft/azsmb/data"

	gcc -O2 -Wall -Wextra "$SOURCE_DIR/src/mount.azsmb.c" \
		-o "$OUTPUT_DIR/staging/deb/sbin/mount.azsmb"
	install -m 0755 "$SOURCE_DIR/src/mountscript.sh" \
		"$OUTPUT_DIR/staging/deb/opt/microsoft/azsmb/mountscript.sh"
	install -m 0644 "$SOURCE_DIR/lib/common.sh" \
		"$OUTPUT_DIR/staging/deb/opt/microsoft/azsmb/common.sh"
	cp "$SOURCE_DIR/packaging/azsmb/DEBIAN/"* "$OUTPUT_DIR/staging/deb/DEBIAN/"
	sed -i \
		-e "s/AZSMB_VERSION/$AZSMB_RELEASE_VERSION/g" \
		-e "s/AZSMB_ARCH/$DEB_ARCH/g" \
		"$OUTPUT_DIR/staging/deb/DEBIAN/control"
	chmod 0755 "$OUTPUT_DIR/staging/deb/DEBIAN/postinst" "$OUTPUT_DIR/staging/deb/DEBIAN/prerm"

	mkdir -p "$OUTPUT_DIR/deb"
	dpkg-deb --root-owner-group --build \
		"$OUTPUT_DIR/staging/deb" \
		"$OUTPUT_DIR/deb/azsmb_${AZSMB_RELEASE_VERSION}_${DEB_ARCH}.deb"
fi

if [[ "$AZSMB_PACKAGE_FORMAT" == "all" || "$AZSMB_PACKAGE_FORMAT" == "rpm" ]]; then
	if ! command -v rpmbuild >/dev/null 2>&1; then
		printf 'rpmbuild is required for RPM package generation\n' >&2
		exit 1
	fi
	gcc -O2 -Wall -Wextra "$SOURCE_DIR/src/mount.azsmb.c" \
		-o "$OUTPUT_DIR/staging/mount.azsmb"
	RPM_TOPDIR="$OUTPUT_DIR/staging/rpmbuild"
	mkdir -p "$RPM_TOPDIR/BUILD" "$RPM_TOPDIR/BUILDROOT" "$RPM_TOPDIR/RPMS" \
		"$RPM_TOPDIR/SOURCES" "$RPM_TOPDIR/SPECS" "$RPM_TOPDIR/SRPMS"
	cp "$OUTPUT_DIR/staging/mount.azsmb" "$RPM_TOPDIR/SOURCES/"
	cp "$SOURCE_DIR/src/mountscript.sh" "$RPM_TOPDIR/SOURCES/"
	cp "$SOURCE_DIR/lib/common.sh" "$RPM_TOPDIR/SOURCES/"
	cp "$SOURCE_DIR/LICENSE" "$RPM_TOPDIR/SOURCES/"
	sed \
		-e "s/AZSMB_VERSION/$AZSMB_RELEASE_VERSION/g" \
		-e "s/AZSMB_ARCH/$RPM_ARCH/g" \
		"$SOURCE_DIR/packaging/azsmb/RPM/azsmb.spec" > "$RPM_TOPDIR/SPECS/azsmb.spec"
	rpmbuild --define "_topdir $RPM_TOPDIR" -bb "$RPM_TOPDIR/SPECS/azsmb.spec"
	mkdir -p "$OUTPUT_DIR/rpm"
	find "$RPM_TOPDIR/RPMS" -type f -name 'azsmb-*.rpm' \
		-exec cp {} "$OUTPUT_DIR/rpm/" \;
fi