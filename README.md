# AZSMB mount helper

AZSMB is a Linux mount helper for Azure Files SMB shares. It delegates to the
standard CIFS mount path while applying Azure Files defaults and supporting
storage-account-key and managed-identity authentication.

## Status

This project is under active development and is not ready for production use.

## Mount examples

Storage-account-key authentication uses a root-readable CIFS credentials file:

```bash
sudo mount -t azsmb \
	//<storage-account>.file.core.windows.net/<share> /mnt/azurefiles \
	-o credentials=/etc/smbcredentials/<storage-account>.cred
```

AZSMB can also create the per-account credential file from one or both storage
account keys. `key2` requires Linux kernel 6.9 or later:

```bash
sudo mount -t azsmb \
	//<storage-account>.file.core.windows.net/<share> /mnt/azurefiles \
	-o key1=<primary-key>,key2=<secondary-key>
```

The helper parses the storage account name from the server FQDN and atomically
writes `/etc/smbcredentials/<storage-account>.cred` with mode `0600`. The file
contains `username=<storage-account>`, `password=<key1>`, and, when supplied,
`password2=<key2>`. Only the resulting `credentials=` option is passed to CIFS;
`key1` and `key2` are removed from the delegated option list.

To rotate a key on an existing dual-key mount, pass `remount` with both current
key values and change exactly one of them. AZSMB compares `key1` with the stored
`password` and `key2` with the stored `password2`. It rewrites the credential
file with the unchanged key as `password` and the changed key as `password2`,
then delegates the remount with only `password2=<changed-key>`. This remount
operation requires cifs-utils 7.2 or later:

```bash
sudo mount -t azsmb \
	//<storage-account>.file.core.windows.net/<share> /mnt/azurefiles \
	-o remount,key1=<new-primary-key>,key2=<new-secondary-key>
```

The remount is rejected if neither key changed, both keys changed, or the
per-account credential file does not already exist.

System-assigned managed identity:

```bash
sudo mount -t azsmb \
	//<storage-account>.file.core.windows.net/<share> /mnt/azurefiles \
	-o client_id=system
```

User-assigned managed identity:

```bash
sudo mount -t azsmb \
	//<storage-account>.file.core.windows.net/<share> /mnt/azurefiles \
	-o client_id=<managed-identity-client-id>
```

`client_id` cannot be combined with `credentials`, `username`, `password`, or
`password2`.

Managed-identity mounts require the `azfilesauth` package and the Azure-side
SMBOAuth, identity assignment, and RBAC configuration described in the Azure
Files documentation.

## Option policy

When absent, AZSMB adds `nosharesock`, `actimeo=30`, and `mfsymlinks`. It does
not add `vers=3.1.1` or `serverino`.

AZSMB adds `max_channels=4` only for Microsoft-documented distro and kernel
combinations. It adds `rasize=8388608` on kernel 6.4 or later.

## Tests

Build packages locally in Docker containers:

```bash
AZSMB_RELEASE_VERSION=0.1.0 bash tests/containers/build_packages.sh
```

Copy the resulting DEB/RPM artifacts and the `lib/`, `src/`, and `tests/`
directories to `vmname`. The repository itself is not required
on the VM. Run all package and unit-test validation in distro containers there:

```bash
AZSMB_BUNDLE_ROOT=/tmp/azsmb-validation \
	bash /tmp/azsmb-validation/tests/containers/run_validation_on_vm.sh
```

The public-container matrix covers Ubuntu 22.04, Ubuntu 24.04, Azure Linux 3.0,
Rocky Linux 9.6 as the RHEL-compatible RPM target, and SLES 15 SP6. A
subscription-enabled RHEL 9.6 image is required for direct RHEL validation
because public UBI repositories do not include `cifs-utils`. Per-distro logs
and status files are written under
`/tmp/azsmb-test-results` by default. Set `AZSMB_CONTAINER_TIMEOUT` to change
the default 1,200-second limit for each distro build. Set
`AZSMB_DOCKER_NO_CACHE=1` when a clean dependency rebuild is required.

Live mount E2E tests must also run on the Azure VM `vmname`. Do not run them on
a development workstation. Use
`tests/e2e/run_on_azure_vm.sh` for host-level mount tests. The default guest
hostname guard is `vmname`; override it with `AZSMB_EXPECTED_HOSTNAME`
only when the Azure VM has been deliberately renamed at the guest OS level.

The runner requires `AZURE_SUBSCRIPTION_ID` and `AZURE_RESOURCE_GROUP`. It uses
`AZSMB_REMOTE_REPO_PATH` when the repository has a non-default path on the VM.

```bash
AZURE_SUBSCRIPTION_ID=<subscription-id> \
AZURE_RESOURCE_GROUP=<resource-group> \
bash tests/e2e/run_on_azure_vm.sh
```

E2E tests take their Azure inputs from environment variables. Storage-key
testing requires `AZURE_STORAGE_ACCOUNT`, `AZURE_FILE_SHARE`, and
`AZSMB_CREDENTIAL_FILE`, which must refer to a root-readable file already on
the VM. Storage keys are never passed through Azure VM Run Command.
When the test is launched directly on the VM, set `AZSMB_KEY1` and optionally
`AZSMB_KEY2` to exercise generated credentials. Set `AZSMB_TEST_REMOUNT=1` and
optionally `AZSMB_REMOUNT_KEY1`/`AZSMB_REMOUNT_KEY2` to exercise credential-file
replacement and remount behavior.
Managed-identity testing requires
`AZURE_STORAGE_ACCOUNT`, `AZURE_FILE_SHARE`, and `AZSMB_MI_CLIENT_ID`; use
`AZSMB_MI_CLIENT_ID=system` for the system-assigned identity.

`tests/e2e/setup_azure_resources.sh` can idempotently prepare system- and
user-assigned identities, enable SMBOAuth, and add the required role at storage
account scope. Its paired cleanup script deletes only a user-assigned identity
tagged as created by that specific test run. Set `AZURE_STORAGE_RESOURCE_GROUP`
when the storage account is not in the VM's `AZURE_RESOURCE_GROUP`.