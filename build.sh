#!/bin/bash

set -e

ROOTFS_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
DISK_IMAGE_NAME=arch-linux-arm-sp11.img
DISK_IMAGE_SIZE_MB=6144

KERNEL_PACKAGE_VERSION=6.15.4-1

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
		bsdtar
		curl
		mkfs.fat
		partprobe
		sfdisk
		makepkg
	)

	for tool in ${tools[@]}; do
		if ! command -v $tool >/dev/null 2>&1; then
			echo $tool not found - please install it!
			exit 1
		fi
	done
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

	partprobe $loopdev

	mkfs.fat -F32 ${loopdev}p1 -n ARCH
	mkfs.ext4 ${loopdev}p2

	mount ${loopdev}p2 build/root
}

function unmount_and_detach {
	chroot build/root /bin/bash -c "killall -wv gpg-agent"
	umount --recursive --detach-loop build/root
	echo Disk image at $loopdev detached
}

function arch_setup {
	bsdtar -xpvf build/rootfs.tar.gz -C build/root

	mount -t proc /proc build/root/proc/
	mount -t sysfs /sys build/root/sys/
	mount --bind /dev build/root/dev/
	mount --bind /dev/pts build/root/dev/pts/
	mkdir -p build/root/boot/efi
	mount ${loopdev}p1 build/root/boot/efi

	cp sp11-grab-fw.bat build/root/boot/efi/

	# Copy kernel, headers and firmware copy script
	cp linux-aarch64-jhovold/linux-aarch64-jhovold-${KERNEL_PACKAGE_VERSION}-aarch64.pkg.tar.xz build/root/var/cache/pacman/pkg/
	cp linux-aarch64-jhovold/linux-aarch64-jhovold-headers-${KERNEL_PACKAGE_VERSION}-aarch64.pkg.tar.xz build/root/var/cache/pacman/pkg/
	cp sp11-grab-fw.sh build/root/usr/local/sbin/sp11-grab-fw

	# Install pacman hook to patch GRUB script and insert SP11 dtb, and fixup Wi-Fi firmware
	cp -r hooks build/root/etc/pacman.d/

	# Chroot into Arch Linux and install some useful tools
	chroot build/root /bin/bash <<-'EOF'
	set -e

	mv /etc/resolv.conf{,.bak}
	echo "nameserver 1.1.1.1" > /etc/resolv.conf

	echo FONT=ter-132n >> /etc/vconsole.conf
	echo LANG=en_US.UTF-8 >> /etc/locale.conf
	sed -i '/#en_US.UTF-8/s/^#\(\S.*\)/\1/' /etc/locale.gen
	locale-gen

	pacman-key --init
	pacman-key --populate archlinuxarm
	pacman -Rcnus --noconfirm linux-aarch64
	pacman -Syu --noconfirm \
			base-devel \
			cabextract \
			git \
			grub \
			iw \
			iwd \
			jq \
			linux-firmware-qcom \
			python \
			sudo \
			terminus-font \
			efibootmgr \
			dosfstools \
			vim
	# install kernel and headers
	pacman --noconfirm -U /var/cache/pacman/pkg/linux-aarch64-jhovold-*-aarch64.pkg.tar.xz

	# Wi-Fi setup with iwd/ath12k bug workaround: https://bugzilla.kernel.org/show_bug.cgi?id=218733
	mkdir /etc/iwd
	cat <<-EOF2 > /etc/iwd/main.conf
			[General]
			EnableNetworkConfiguration=true
			ControlPortOverNL80211=false
	EOF2

	systemctl enable iwd

	sed -i 's/^MODULES=().*$/MODULES=(tcsrcc-x1e80100 phy-qcom-qmp-pcie phy-qcom-qmp-usb phy-qcom-qmp-usbc phy-qcom-eusb2-repeater phy-qcom-snps-eusb2 phy-qcom-qmp-combo surface-hid surface-aggregator surface-aggregator-registry surface-aggregator-hub)/' /etc/mkinitcpio.conf
	sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="clk_ignore_unused pd_ignore_unused loglevel=7"/' /etc/default/grub

	grub-install --target=arm64-efi --efi-directory=/boot/efi --removable
	grub-mkconfig > /boot/grub/grub.cfg

	EOF
}

function build_kernel {
	local DIR=$(pwd)
	cd linux-aarch64-jhovold
	if [ ! -f "linux-aarch64-jhovold-${KERNEL_PACKAGE_VERSION}-aarch64.pkg.tar.xz" ]; then
		su -c "makepkg -Cfs" alarm
	fi
	cd $DIR
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
