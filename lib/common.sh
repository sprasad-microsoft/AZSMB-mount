#!/bin/bash

AZSMB_OS_RELEASE_FILE="${AZSMB_OS_RELEASE_FILE:-/etc/os-release}"

azsmb_error()
{
	printf 'azsmb: %s\n' "$*" >&2
}

azsmb_kernel_release()
{
	if [[ -n "${AZSMB_KERNEL_RELEASE:-}" ]]; then
		printf '%s\n' "$AZSMB_KERNEL_RELEASE"
	else
		uname -r
	fi
}

azsmb_environment()
{
	if [[ -n "${AZSMB_ENVIRONMENT:-}" ]]; then
		printf '%s\n' "$AZSMB_ENVIRONMENT"
	elif [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
		printf 'aks\n'
	else
		printf 'vm\n'
	fi
}

azsmb_os_value()
{
	local key="$1"
	local value

	if [[ ! -r "$AZSMB_OS_RELEASE_FILE" ]]; then
		azsmb_error "cannot read $AZSMB_OS_RELEASE_FILE"
		return 1
	fi

	value=$(sed -n "s/^${key}=//p" "$AZSMB_OS_RELEASE_FILE" | head -n 1)
	value="${value%\"}"
	value="${value#\"}"
	printf '%s\n' "$value"
}

azsmb_version_ge()
{
	local actual="$1"
	local minimum="$2"

	[[ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n 1)" == "$minimum" ]]
}

azsmb_mi_distro_supported()
{
	local distro
	local version

	distro=$(azsmb_os_value ID)
	version=$(azsmb_os_value VERSION_ID)
	if [[ "$distro" == "sles" || "$distro" == "suse" ]]; then
		version="${version/-SP/.}"
	fi

	case "$distro" in
		azurelinux)
			azsmb_version_ge "$version" "3.0"
			;;
		ubuntu)
			[[ "$version" == "22.04" || "$version" == "24.04" ]]
			;;
		rhel)
			azsmb_version_ge "$version" "9.6"
			;;
		sles|suse)
			azsmb_version_ge "$version" "15.6"
			;;
		*)
			return 1
			;;
	esac
}

azsmb_multichannel_minimum()
{
	local distro
	local version
	local environment

	distro=$(azsmb_os_value ID)
	version=$(azsmb_os_value VERSION_ID)
	environment=$(azsmb_environment)

	case "${distro}:${version}:${environment}" in
		ubuntu:24.04:aks)
			printf '6.8.0-1042\n'
			;;
		ubuntu:24.04:vm)
			printf '6.14.0-1017\n'
			;;
		ubuntu:22.04:vm)
			printf '6.8.0-1044\n'
			;;
		azurelinux:3.0:vm|azurelinux:3.0:aks)
			printf '6.6.106.1\n'
			;;
		rhel:9.7:vm)
			printf '5.14.0-611.5.1.el9_7\n'
			;;
		*)
			return 1
			;;
	esac
}

azsmb_multichannel_supported()
{
	local minimum

	minimum=$(azsmb_multichannel_minimum) || return 1
	azsmb_version_ge "$(azsmb_kernel_release)" "$minimum"
}

azsmb_rasize_supported()
{
	local kernel_release
	local major
	local minor

	kernel_release=$(azsmb_kernel_release)
	if [[ ! "$kernel_release" =~ ^([0-9]+)\.([0-9]+) ]]; then
		return 1
	fi

	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	(( major > 6 || (major == 6 && minor >= 4) ))
}

azsmb_option_present()
{
	local options="$1"
	local key="$2"
	local option
	local -a option_list

	IFS=',' read -r -a option_list <<< "$options"
	for option in "${option_list[@]}"; do
		if [[ "$option" == "$key" || "$option" == "$key="* ]]; then
			return 0
		fi
	done

	return 1
}

azsmb_option_value()
{
	local options="$1"
	local key="$2"
	local option
	local -a option_list

	IFS=',' read -r -a option_list <<< "$options"
	for option in "${option_list[@]}"; do
		if [[ "$option" == "$key="* ]]; then
			printf '%s\n' "${option#*=}"
			return 0
		fi
	done

	return 1
}

azsmb_remove_option()
{
	local options="$1"
	local key="$2"
	local option
	local result=""
	local -a option_list

	IFS=',' read -r -a option_list <<< "$options"
	for option in "${option_list[@]}"; do
		if [[ "$option" == "$key" || "$option" == "$key="* ]]; then
			continue
		fi
		if [[ -n "$result" ]]; then
			result+=","
		fi
		result+="$option"
	done

	printf '%s\n' "$result"
}

azsmb_append_option()
{
	local options="$1"
	local option="$2"
	local key="${option%%=*}"

	if azsmb_option_present "$options" "$key"; then
		printf '%s\n' "$options"
	elif [[ -n "$options" ]]; then
		printf '%s,%s\n' "$options" "$option"
	else
		printf '%s\n' "$option"
	fi
}

azsmb_add_default_options()
{
	local options="$1"
	local value

	if value=$(azsmb_option_value "$options" max_channels); then
		if [[ "$value" != "4" ]]; then
			azsmb_error "max_channels must be 4 when specified"
			return 1
		fi
	fi

	if value=$(azsmb_option_value "$options" rasize); then
		if [[ "$value" != "8388608" ]]; then
			azsmb_error "rasize must be 8388608 when specified"
			return 1
		fi
	fi

	options=$(azsmb_append_option "$options" "nosharesock")
	options=$(azsmb_append_option "$options" "actimeo=30")
	options=$(azsmb_append_option "$options" "mfsymlinks")

	if azsmb_multichannel_supported; then
		options=$(azsmb_append_option "$options" "max_channels=4")
	fi

	if azsmb_rasize_supported; then
		options=$(azsmb_append_option "$options" "rasize=8388608")
	fi

	printf '%s\n' "$options"
}