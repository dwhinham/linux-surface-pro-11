#!/bin/bash

set -e

GITHUB_REPO=WOA-Project/Qualcomm-Reference-Drivers
DEVICE=Surface/8380_DEN

DRIVER_REPO_API_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/${DEVICE}"
DRIVER_REPO_DOWNLOAD_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/master/${DEVICE}"

SOURCE_PREFIX="Windows/System32/DriverStore/FileRepository"
DEST_PREFIX="/lib/firmware"

#	Source file			Source .cab						Destination (under /lib/firmware/)
firmware=(
	"qcdxkmsuc8380.mbn"	"qcdx8380.cab"					"qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"
	"adsp_dtbs.elf"		"surfacepro_ext_adsp8380.cab"	"qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn"
	"qcadsp8380.mbn"	"surfacepro_ext_adsp8380.cab"	"qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn"
	"cdsp_dtbs.elf"		"qcnspmcdm_ext_cdsp8380.cab"	"qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn"
	"qccdsp8380.mbn"	"qcnspmcdm_ext_cdsp8380.cab"	"qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn"
)

function check_root {
	if [ "$EUID" -ne 0 ]; then
		echo "This script must be run as root."
		echo "Please try 'sudo $0'."
		exit 1
	fi
}

function check_tools_dl {
	local tools=(
		cabextract
		curl
		jq
	)

	for tool in "${tools[@]}"; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "$tool" not found - please install it!
			exit 1
		fi
	done 
}

function check_tools_win {
	if ! command -v dislocker >/dev/null 2>&1; then
		echo "dislocker not found - please install it!"
		exit 1
	fi
}

function move_adsp_fw {
	# If booted from USB, disable the ADSP firmware otherwise we will get a boot failure
	# (the ADSP will reset the USB devices mid-boot and cause issues)
	root_device=$(findmnt -n -o SOURCE /)
	root_drive=$(lsblk -no PKNAME "$root_device")

	if [[ ! "$root_drive" == nvme* ]]; then
		mv $DEST_PREFIX/qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn{,.disabled}

		cat <<-EOF

		$(echo -e "\e[1;31mWARNING:\e[0m")
		Current root partition is NOT on an NVMe drive: $root_drive

		The ADSP firmware has been installed to '$DEST_PREFIX/qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn.disabled'.
		This is to avoid boot failure because you ran this script inside a live USB environment.
		Rename this file from 'adsp_dtb.mbn.disabled' to 'adsp_dtb.mbn' if you want to enable it after installing to NVMe.
		EOF
	fi
}

function grab_fw_download {
	check_tools_dl

	latest=$(curl -sL $DRIVER_REPO_API_URL \
		| jq -r '.[] | select(.type == "dir") | .name' \
		| sort -t '.' -k1,1n -k2,2n -k3,3n -k4,4n \
		| tail -n 1)

	echo "Latest driver set version: $latest"

	tmp=$(mktemp -d)
	mkdir -p "$tmp"

	for ((i=0; i<${#firmware[@]}; i+=3)); do
		src=${firmware[i]}
		cab=${firmware[i+1]}
		dst="$tmp/firmware/${firmware[i+2]}"

		dst_dir=$(dirname "$dst")

		if [ ! -f "$tmp/$cab" ]; then
			echo "Downloading $cab..."
			curl -#L "$DRIVER_REPO_DOWNLOAD_URL/$latest/$cab" -o "$tmp/$cab"
		fi

		echo "Extracting $src..."
		cabextract "$tmp/$cab" -F "$src" -d "$tmp" -q 2>/dev/null

		mkdir -p "$dst_dir"
		mv "$tmp/$src" "$dst"
	done

	cp -rv "$tmp"/firmware/* "$DEST_PREFIX"
	rm -rf "$tmp"

	move_adsp_fw
}

function grab_fw_windows {
	check_tools_win

	partition=$(lsblk -l -o NAME,FSTYPE | grep nvme0n1 | grep BitLocker | cut -d" " -f1)
	if [ -z "$partition" ]; then
		printf "Couldn't find Windows system partition (BitLocker)" >&2
		exit 1
	fi

	echo "Mounting Windows drive..."

	tmp=$(mktemp -d)
	mkdir -p "$tmp/dislocker" "$tmp/windows"

	dislocker --readonly "/dev/$partition" "$tmp/dislocker"
	mount -t ntfs -oloop,ro "$tmp/dislocker/dislocker-file" "$tmp/windows"

	mkdir -p ${DEST_PREFIX}/qcom/x1e80100/microsoft/Denali
	mkdir -p ${DEST_PREFIX}/ath12k/WCN7850/hw2.0

	echo "Searching for firmware..."
	for ((i=0; i<${#firmware[@]}; i+=3)); do
		src=${firmware[i]}
		dst=${firmware[i+2]}

		# There may be multiple versions of the firmware; try to grab this latest version of each firmware file
		latest_file=$(find "$tmp/windows/$SOURCE_PREFIX" -type f -name "$src" -printf "%T@ %p\n" | sort -nr | awk 'NR==1{print $2}')

		cp -v "$latest_file" "$DEST_PREFIX/$dst"
	done

	echo "Unmounting..."
	umount "$tmp/windows"
	umount "$tmp/dislocker"
	rm -r "$tmp"

	move_adsp_fw
}

function print_usage {
	cat <<-EOF
		Usage: $0 [--download | --win]
		    -d, --download (default): attempts to download firmware from the Internet
		    -w, --win: attempts to extract firmware from a Windows/BitLocker driver
	EOF
	exit 0
}

check_root

case "$1" in
    -d|--download) grab_fw_download ;;
    -w|--win) grab_fw_windows ;;
	-h|--help) print_usage ;;
    *) grab_fw_download ;;
esac
