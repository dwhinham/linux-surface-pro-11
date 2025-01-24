#!/bin/bash

set -e

ROOTFS_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
DISK_IMAGE_NAME=arch-linux-arm-sp11.img
DISK_IMAGE_SIZE_MB=4096

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
	if ! command -v bsdtar >/dev/null 2>&1; then
		echo bsdtar not found - please install it!
		exit 1
	fi

	if ! command -v sfdisk >/dev/null 2>&1; then
		echo sfdisk not found - please install it!
		exit 1
	fi

	if ! command -v mkfs.fat >/dev/null 2>&1; then
		echo mkfs.fat not found - please install dosfstools!
		exit 1
	fi
}

function create_dirs {
	mkdir -p build/root
}

function get_rootfs {
	if [ ! -f build/rootfs.tar.gz ]; then
		curl -fLo build/rootfs.tar.gz "$ROOTFS_URL" 2>&1
	fi
}

function prepare_disk_image {
	if [ ! -f build/$DISK_IMAGE_NAME ]; then
		dd if=/dev/zero of=build/$DISK_IMAGE_NAME bs=1M count=$DISK_IMAGE_SIZE_MB status=progress
		sfdisk build/$DISK_IMAGE_NAME <<-EOF
			label: dos
			size=512M, type=uefi, bootable
			size=+
			EOF
	fi
}

function attach_and_mount {
	loopdev=`losetup --partscan --find --show build/$DISK_IMAGE_NAME`
	echo Disk image attached at $loopdev

	sleep 1

	mkfs.fat -F32 ${loopdev}p1 -n ARCH
	mkfs.ext4 ${loopdev}p2

	mount ${loopdev}p2 build/root
}

function unmount_and_detach {
	umount --recursive build/root
	losetup -d $loopdev
	echo Disk image at $loopdev detached
}

function arch_setup {
	bsdtar -xpvf build/rootfs.tar.gz -C build/root

	mount -t proc /proc build/root/proc/
	mount -t sysfs /sys build/root/sys/
	mount -o bind /dev build/root/dev/
	mkdir -p build/root/mnt/efi
	mount ${loopdev}p1 build/root/mnt/efi

	cp grab_fw.bat build/root/mnt/efi/

	# Copy kernel, modules, and dtbs
	cp -r build/boot/* build/root/boot/
	cp -r build/modules/lib/modules/* build/root/lib/modules/

	# Chroot into Arch Linux and install some useful tools
	chroot build/root /bin/bash <<-'EOF'
		mv /etc/resolv.conf{,.bak}
		echo "nameserver 1.1.1.1" > /etc/resolv.conf

		pacman-key --init
		pacman-key --populate archlinuxarm
		pacman -D --asexplicit linux-firmware mkinitcpio
		pacman -Rcnus --noconfirm linux-aarch64
		pacman -Syu --noconfirm \
			linux-firmware-qcom \
			grub \
			terminus-font

		pacman -Scc --noconfirm

		echo FONT=ter-132n >> /etc/vconsole.conf

		sed -i 's/^MODULES=().*$/MODULES=(tcsrcc-x1e80100 phy-qcom-qmp-pcie phy-qcom-qmp-usb phy-qcom-qmp-usbc phy-qcom-eusb2-repeater phy-qcom-snps-eusb2 phy-qcom-qmp-combo surface-hid surface-aggregator surface-aggregator-registry surface-aggregator-hub)/' /etc/mkinitcpio.conf
		sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="clk_ignore_unused pd_ignore_unused loglevel=7"/' /etc/default/grub

		kernel=$(ls /boot | grep '^vmlinuz')
		kversion="${kernel#vmlinuz-}"
		mkinitcpio -k $kversion -g /boot/initramfs-$kversion.img -v
		grub-install --target=arm64-efi --efi-directory=/mnt/efi --removable
		grub-mkconfig > /boot/grub/grub.cfg
		sed -i '/initrd[[:space:]]*\/boot\/.*\.img/a \	devicetree /boot/dtbs/'$kversion'/qcom/x1e80100-microsoft-denali.dtb' /boot/grub/grub.cfg

		killall -wv gpg-agent
	EOF
}

function build_kernel {
	if [ ! -f build/boot/vmlinuz* ]; then
		git clone https://github.com/jhovold/linux.git build/linux-jhovold --single-branch --branch wip/x1e80100-6.13 --depth 1
	
		for p in kernel_patches/*; do
			git -C build/linux-jhovold apply < $p
		done

		cp kernel_config build/linux-jhovold/.config

		mkdir -p build/boot build/modules
		export INSTALL_PATH=../boot
		export INSTALL_MOD_PATH=../modules

		make -C build/linux-jhovold -j12
		make -C build/linux-jhovold modules_install
		make -C build/linux-jhovold dtbs_install
		make -C build/linux-jhovold install
	fi
}

check_root
check_arch
check_tools

create_dirs
build_kernel

get_rootfs
prepare_disk_image
attach_and_mount
arch_setup
unmount_and_detach
