#!/bin/bash

set -e

src_prefix="Windows/System32/DriverStore/FileRepository"
dst_prefix="/lib/firmware"

firmware=(
	"qcdxkmsuc8380.mbn"	"qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"
	"adsp_dtbs.elf"		"qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn"
	"qcadsp8380.mbn"	"qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn"
	"cdsp_dtbs.elf"		"qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn"
	"qccdsp8380.mbn"	"qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn"
	"wlanfw20.mbn"		"ath12k/WCN7850/hw2.0/amss.bin"
	"bdwlan.elf"		"ath12k/WCN7850/hw2.0/board.bin"
	"phy_ucode20.elf"	"ath12k/WCN7850/hw2.0/m3.bin"
)

if [ "$EUID" -ne 0 ]; then
	echo "This script must be run as root."
	echo "Please try 'sudo $0'."
	exit 1
fi

if ! command -v dislocker >/dev/null 2>&1; then
	echo "dislocker not found - please install it!"
	exit 1
fi

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

mkdir -p ${dst_prefix}/qcom/x1e80100/microsoft/Denali
mkdir -p ${dst_prefix}/ath12k/WCN7850/hw2.0

echo "Searching for firmware..."
for ((i=0; i<${#firmware[@]}; i+=2)); do
	src=${firmware[i]}
	dst=${firmware[i+1]}

	# There may be multiple versions of the firmware; try to grab this latest version of each firmware file
	latest_file=$(find "$tmp/windows/$src_prefix" -type f -name "$src" -printf "%T@ %p\n" | sort -nr | awk 'NR==1{print $2}')

	cp -v "$latest_file" "$dst_prefix/$dst"
done

echo "Unmounting..."
umount "$tmp/windows"
umount "$tmp/dislocker"
rm -r "$tmp"

# If booted from USB, disable the ADSP firmware otherwise we will get a boot failure
# (the ADSP will reset the USB devices mid-boot and cause issues)
root_device=$(findmnt -n -o SOURCE /)
root_drive=$(lsblk -no PKNAME "$root_device")

if [[ ! "$root_drive" == nvme* ]]; then
	mv $dst_prefix/qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn{,.disabled}

	cat <<-EOF

	$(echo -e "\e[1;31mWARNING:\e[0m")
	Current root partition is NOT on an NVMe drive: $root_drive

	The ADSP firmware has been installed to '$dst_prefix/qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn.disabled'.
	This is to avoid boot failure because you ran this script inside a live USB environment.
	Rename this file from 'adsp_dtb.mbn.disabled' to 'adsp_dtb.mbn' if you want to enable it after installing to NVMe.
	EOF
fi
