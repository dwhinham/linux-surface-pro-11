#!/bin/bash

set -e

DISK_IMAGE_NAME=arch-linux-arm-sp11.img

function check_root {
	if [ "$EUID" -ne 0 ]; then
		echo "This script must be run as root."
		echo "Please try 'sudo $0'."
		exit 1
	fi
}

function check_arch {
	if [ ! `uname -m` = "aarch64" ]; then
		echo "This script needs to be run on an aarch64 machine!"
		exit 1
	fi
}

function check_tools {
	local tools=(
		partprobe
	)

	for tool in ${tools[@]}; do
		if ! command -v $tool >/dev/null 2>&1; then
			echo $tool not found - please install it!
			exit 1
		fi
	done
}

function attach_and_mount {
	loopdev=`losetup --partscan --find --show build/$DISK_IMAGE_NAME`
	echo Disk image attached at $loopdev

	partprobe $loopdev

	mount ${loopdev}p2 build/root
}

function unmount_and_detach {
	umount --recursive --detach-loop build/root
	echo Disk image at $loopdev detached
}

function arch_chroot {
	mount -t proc /proc build/root/proc/
	mount -t sysfs /sys build/root/sys/
	mount --bind /dev build/root/dev/
	mount --bind /dev/pts build/root/dev/pts/
	mkdir -p build/root/boot/efi
	mount ${loopdev}p1 build/root/boot/efi

	# Chroot into Arch Linux
	chroot build/root /bin/bash
}

check_root
check_arch
check_tools

attach_and_mount
arch_chroot
unmount_and_detach
