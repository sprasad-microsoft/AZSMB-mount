Name: azsmb
Version: AZSMB_VERSION
Release: 1
Summary: Mount helper for Azure Files SMB shares
License: MIT
URL: https://github.com/Azure/AZSMB-mount
BuildArch: AZSMB_ARCH
Requires: bash
Requires: util-linux
Requires: cifs-utils
Requires: azfilesauth

%description
AZSMB provides a mount helper for Azure Files SMB shares, including managed
identity authentication and kernel-aware mount option selection.

%prep

%build

%install
mkdir -p %{buildroot}/sbin
mkdir -p %{buildroot}/opt/microsoft/azsmb/data
mkdir -p %{buildroot}%{_licensedir}/%{name}
install -m 0755 %{_sourcedir}/mount.azsmb %{buildroot}/sbin/mount.azsmb
install -m 0755 %{_sourcedir}/mountscript.sh %{buildroot}/opt/microsoft/azsmb/mountscript.sh
install -m 0644 %{_sourcedir}/common.sh %{buildroot}/opt/microsoft/azsmb/common.sh
install -m 0644 %{_sourcedir}/LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license %{_licensedir}/%{name}/LICENSE
/sbin/mount.azsmb
/opt/microsoft/azsmb/mountscript.sh
/opt/microsoft/azsmb/common.sh
%dir %attr(0750,root,root) /opt/microsoft/azsmb/data

%post
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files azfilesrefresh.service >/dev/null 2>&1; then
	systemctl enable azfilesrefresh.service >/dev/null 2>&1 || :
fi

%changelog
* Fri Sep 11 2026 Azure Files Team - 0.1.0-1
- Initial package