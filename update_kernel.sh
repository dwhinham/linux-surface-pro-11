#!/bin/bash

set -e

function check_root {
	if [ "$EUID" -ne 0 ]; then
		echo "This script must be run as root."
		echo "Please try 'sudo $0'."
		exit 1
	fi
}

function update_kernel {
	cp -r build/boot/* /boot/
	cp -r build/modules/lib/modules/* /lib/modules/

	kernel=$(ls /boot | grep '^vmlinuz')
	kversion="${kernel#vmlinuz-}"
	mkinitcpio -k $kversion -g /boot/initramfs-$kversion.img -v
	depmod -a
}

check_root
update_kernel