#!/bin/bash

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "$SCRIPT_DIR/../lib/common.sh" ]]; then
	. "$SCRIPT_DIR/../lib/common.sh"
else
	. "$SCRIPT_DIR/common.sh"
fi

AZSMB_AUTH_CONFIG_FILE="${AZSMB_AUTH_CONFIG_FILE:-/etc/azfilesauth/config.yaml}"
AZSMB_CREDENTIAL_DIR="${AZSMB_CREDENTIAL_DIR:-/etc/smbcredentials}"

azsmb_usage()
{
	azsmb_error "usage: mount -t azsmb //<account>.file.<endpoint>/<share> <mountpoint> [-o options]"
}

azsmb_validate_source()
{
	local source="$1"
	local path
	local host
	local share

	if [[ "$source" != //* ]]; then
		azsmb_error "source must be an Azure Files UNC path"
		return 1
	fi

	path="${source#//}"
	host="${path%%/*}"
	share="${path#*/}"
	if [[ -z "$host" || -z "$share" || "$share" == "$path" || "$share" == */* ]]; then
		azsmb_error "source must contain exactly one Azure file share"
		return 1
	fi

	if [[ "$host" =~ ^[a-z0-9][a-z0-9-]{1,22}[a-z0-9](\.privatelink)?\.file(\.[a-z0-9-]+)?\.core\.(windows\.net|usgovcloudapi\.net|chinacloudapi\.cn)$ ]]; then
		return 0
	fi
	if [[ "$host" =~ ^[a-z0-9][a-z0-9-]{1,22}[a-z0-9](\.privatelink)?\.file\.storage\.azure\.net$ ]]; then
		return 0
	fi

	azsmb_error "source is not a recognized Azure Files endpoint"
	return 1
}

azsmb_source_host()
{
	local path="${1#//}"

	printf '%s\n' "${path%%/*}"
}

azsmb_storage_account()
{
	local host

	host=$(azsmb_source_host "$1")
	printf '%s\n' "${host%%.*}"
}

azsmb_validate_client_id()
{
	local client_id="$1"

	if [[ "$client_id" == "system" ]]; then
		return 0
	fi

	[[ "$client_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

azsmb_validate_auth_options()
{
	local options="$1"
	local client_id
	local conflicting
	local key1
	local key2

	if client_id=$(azsmb_option_value "$options" client_id); then
		if [[ -z "$client_id" ]]; then
			azsmb_error "client_id must not be empty"
			return 1
		fi
		if ! azsmb_validate_client_id "$client_id"; then
			azsmb_error "client_id must be 'system' or a managed identity client ID"
			return 1
		fi

		for conflicting in credentials username password password2 key1 key2; do
			if azsmb_option_present "$options" "$conflicting"; then
				azsmb_error "client_id cannot be combined with $conflicting"
				return 1
			fi
		done
	fi

	if key2=$(azsmb_option_value "$options" key2); then
		if ! key1=$(azsmb_option_value "$options" key1) || [[ -z "$key1" ]]; then
			azsmb_error "key2 requires key1"
			return 1
		fi
		if [[ -z "$key2" ]]; then
			azsmb_error "key2 must not be empty"
			return 1
		fi
	fi

	if key1=$(azsmb_option_value "$options" key1); then
		if [[ -z "$key1" ]]; then
			azsmb_error "key1 must not be empty"
			return 1
		fi
		for conflicting in credentials username password password2; do
			if azsmb_option_present "$options" "$conflicting"; then
				azsmb_error "key1 cannot be combined with $conflicting"
				return 1
			fi
		done
	fi
}

azsmb_write_credential_file()
{
	local account="$1"
	local credential_file="$2"
	local password="$3"
	local password2="$4"
	local temporary_file

	install -d -o root -g root -m 0700 "$AZSMB_CREDENTIAL_DIR" || {
		azsmb_error "failed to create $AZSMB_CREDENTIAL_DIR"
		return 1
	}
	temporary_file=$(mktemp "$AZSMB_CREDENTIAL_DIR/.${account}.cred.XXXXXX") || {
		azsmb_error "failed to create a temporary credential file"
		return 1
	}
	if ! chmod 0600 "$temporary_file"; then
		rm -f "$temporary_file"
		azsmb_error "failed to secure the temporary credential file"
		return 1
	fi
	if ! {
		printf 'username=%s\n' "$account"
		printf 'password=%s\n' "$password"
		if [[ -n "$password2" ]]; then
			printf 'password2=%s\n' "$password2"
		fi
	} > "$temporary_file"; then
		rm -f "$temporary_file"
		azsmb_error "failed to write the temporary credential file"
		return 1
	fi
	if ! chown root:root "$temporary_file"; then
		rm -f "$temporary_file"
		azsmb_error "failed to secure the temporary credential file"
		return 1
	fi
	mv -f "$temporary_file" "$credential_file" || {
		rm -f "$temporary_file"
		azsmb_error "failed to install $credential_file"
		return 1
	}
}

azsmb_prepare_storage_keys()
{
	local source="$1"
	local options="$2"
	local account
	local changed_key
	local credential_file
	local existing_password
	local existing_password2
	local key1_changed
	local key2_changed
	local key1
	local key2=""
	local unchanged_key

	key1=$(azsmb_option_value "$options" key1) || {
		printf '%s\n' "$options"
		return 0
	}
	if azsmb_option_value "$options" key2 >/dev/null; then
		key2=$(azsmb_option_value "$options" key2)
		if ! azsmb_password2_supported; then
			azsmb_error "key2 requires Linux kernel 6.9 or later"
			return 1
		fi
	fi

	if [[ "$key1" == *$'\n'* || "$key2" == *$'\n'* ]]; then
		azsmb_error "storage account keys must not contain newlines"
		return 1
	fi

	account=$(azsmb_storage_account "$source")
	credential_file="$AZSMB_CREDENTIAL_DIR/$account.cred"

	options=$(azsmb_remove_option "$options" key1)
	options=$(azsmb_remove_option "$options" key2)
	if azsmb_option_present "$options" remount && [[ -n "$key2" ]]; then
		if ! azsmb_dual_key_remount_supported; then
			azsmb_error "dual-key remount requires cifs-utils 7.2 or later"
			return 1
		fi
		if [[ ! -r "$credential_file" ]]; then
			azsmb_error "dual-key remount requires existing $credential_file"
			return 1
		fi
		existing_password=$(sed -n 's/^password=//p' "$credential_file" | head -n 1)
		existing_password2=$(sed -n 's/^password2=//p' "$credential_file" | head -n 1)
		if [[ -z "$existing_password" ]]; then
			azsmb_error "password is missing from $credential_file"
			return 1
		fi

		key1_changed=0
		key2_changed=0
		[[ "$key1" == "$existing_password" ]] || key1_changed=1
		[[ "$key2" == "$existing_password2" ]] || key2_changed=1
		if (( key1_changed + key2_changed != 1 )); then
			azsmb_error "dual-key remount requires exactly one changed key"
			return 1
		fi

		if (( key1_changed )); then
			unchanged_key="$key2"
			changed_key="$key1"
		else
			unchanged_key="$key1"
			changed_key="$key2"
		fi
		azsmb_write_credential_file \
			"$account" "$credential_file" "$unchanged_key" "$changed_key" || return 1
		options=$(azsmb_remove_option "$options" credentials)
		options=$(azsmb_remove_option "$options" password2)
		options=$(azsmb_remove_option "$options" username)
		options=$(azsmb_append_option "$options" "username=$account")
		options=$(azsmb_append_option "$options" "password2=$changed_key")
		printf '%s\n' "$options"
		return 0
	fi

	azsmb_write_credential_file \
		"$account" "$credential_file" "$key1" "$key2" || return 1
	options=$(azsmb_append_option "$options" "credentials=$credential_file")
	printf '%s\n' "$options"
}

azsmb_credential_uid()
{
	local uid

	if [[ ! -r "$AZSMB_AUTH_CONFIG_FILE" ]]; then
		azsmb_error "cannot read $AZSMB_AUTH_CONFIG_FILE"
		return 1
	fi

	uid=$(sed -n 's/^[[:space:]]*USER_UID:[[:space:]]*//p' \
		"$AZSMB_AUTH_CONFIG_FILE" | head -n 1)
	if [[ ! "$uid" =~ ^[0-9]+$ ]]; then
		azsmb_error "USER_UID is missing or invalid in $AZSMB_AUTH_CONFIG_FILE"
		return 1
	fi

	printf '%s\n' "$uid"
}

azsmb_prepare_managed_identity()
{
	local source="$1"
	local options="$2"
	local client_id
	local endpoint
	local security
	local uid

	client_id=$(azsmb_option_value "$options" client_id) || {
		printf '%s\n' "$options"
		return 0
	}

	if ! azsmb_mi_distro_supported; then
		azsmb_error "managed identity mounts are not supported on this distribution"
		return 1
	fi
	if ! command -v azfilesauthmanager >/dev/null 2>&1; then
		azsmb_error "azfilesauth is required for managed identity mounts"
		return 1
	fi
	if security=$(azsmb_option_value "$options" sec); then
		if [[ "$security" != "krb5" ]]; then
			azsmb_error "client_id requires sec=krb5"
			return 1
		fi
	fi

	endpoint="https://$(azsmb_source_host "$source")"
	if [[ "$client_id" == "system" ]]; then
		azfilesauthmanager set "$endpoint" --system >/dev/null || {
			azsmb_error "failed to prepare system-assigned managed identity credentials"
			return 1
		}
	else
		azfilesauthmanager set "$endpoint" --imds-client-id "$client_id" >/dev/null || {
			azsmb_error "failed to prepare user-assigned managed identity credentials"
			return 1
		}
	fi

	uid=$(azsmb_credential_uid) || return 1
	options=$(azsmb_remove_option "$options" client_id)
	options=$(azsmb_remove_option "$options" cruid)
	options=$(azsmb_append_option "$options" "sec=krb5")
	options=$(azsmb_append_option "$options" "cruid=$uid")
	if [[ "$client_id" != "system" ]]; then
		options=$(azsmb_append_option "$options" "username=$client_id")
	fi

	if ! command -v systemctl >/dev/null 2>&1; then
		azsmb_error "systemd is required for managed identity credential refresh"
		return 1
	fi
	systemctl enable --now azfilesrefresh >/dev/null || {
		azsmb_error "failed to enable the azfilesrefresh service"
		return 1
	}
	if ! systemctl is-active --quiet azfilesrefresh; then
		azsmb_error "azfilesrefresh did not become active"
		return 1
	fi

	printf '%s\n' "$options"
}

azsmb_main()
{
	local source
	local mountpoint
	local options=""
	local next_is_options=false
	local argument
	local -a mount_flags=()

	if (( EUID != 0 )); then
		azsmb_error "mount helper must run as root"
		return 1
	fi

	if (( $# < 2 )); then
		azsmb_usage
		return 1
	fi

	source="$1"
	mountpoint="$2"
	shift 2

	for argument in "$@"; do
		if $next_is_options; then
			if [[ -n "$options" ]]; then
				options+=","
			fi
			options+="$argument"
			next_is_options=false
		elif [[ "$argument" == "-o" ]]; then
			next_is_options=true
		else
			mount_flags+=("$argument")
		fi
	done
	if $next_is_options; then
		azsmb_error "-o requires a mount option list"
		return 1
	fi

	azsmb_validate_source "$source" || return 1
	azsmb_validate_auth_options "$options" || return 1
	options=$(azsmb_prepare_storage_keys "$source" "$options") || return 1
	options=$(azsmb_prepare_managed_identity "$source" "$options") || return 1
	options=$(azsmb_add_default_options "$options") || return 1

	exec mount -t cifs "${mount_flags[@]}" -o "$options" "$source" "$mountpoint"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	azsmb_main "$@"
fi