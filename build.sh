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
	local tools=(
		bsdtar
		mkfs.fat
		partprobe
		sfdisk
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
	umount --recursive --detach-loop build/root
	echo Disk image at $loopdev detached
}

function arch_setup {
	bsdtar -xpvf build/rootfs.tar.gz -C build/root

	mount -t proc /proc build/root/proc/
	mount -t sysfs /sys build/root/sys/
	mount --bind /dev build/root/dev/
	mount --bind /dev/pts build/root/dev/pts/
	mkdir -p build/root/mnt/efi
	mount ${loopdev}p1 build/root/mnt/efi

	cp sp11-grab-fw.bat build/root/mnt/efi/

	# Copy kernel, modules, dtbs and firmware copy script
	cp -r build/boot/* build/root/boot/
	cp -r build/modules/lib/modules/* build/root/lib/modules/
	cp sp11-grab-fw.sh build/root/usr/local/sbin/sp11-grab-fw

	# Chroot into Arch Linux and install some useful tools
	chroot build/root /bin/bash <<-'EOF'
		set -e

		mv /etc/resolv.conf{,.bak}
		echo "nameserver 1.1.1.1" > /etc/resolv.conf

		pacman-key --init
		pacman-key --populate archlinuxarm
		pacman -D --asexplicit linux-firmware mkinitcpio
		pacman -Rcnus --noconfirm linux-aarch64
		pacman -Syu --noconfirm \
			base-devel \
			git \
			grub \
			iw \
			iwd \
			linux-firmware-qcom \
			sudo \
			terminus-font

		# Give wheel users (i.e. alarm) no-password sudo access otherwise makepkg won't work
		sed -i 's/^#\s*%wheel\s*ALL=(ALL:ALL)\s*NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

		# Install dislocker from AUR (used for extracting firmware)
		su alarm
			tmp=$(mktemp -d)
			git clone https://aur.archlinux.org/dislocker.git "$tmp/dislocker"
			pushd "$tmp/dislocker"

			# Add missing aarch64 architecture
			sed -i "s/arch=(/arch=('aarch64' /" PKGBUILD
			
			makepkg -si --noconfirm
			popd
			rm -rf "$tmp"
		exit

		pacman -Scc --noconfirm

		# Wi-Fi setup with iwd/ath12k bug workaround: https://bugzilla.kernel.org/show_bug.cgi?id=218733
		mkdir /etc/iwd
		cat <<-EOF2 > /etc/iwd/main.conf
			[General]
			EnableNetworkConfiguration=true
			ControlPortOverNL80211=false
		EOF2

		systemctl enable iwd

		echo FONT=ter-132n >> /etc/vconsole.conf

		sed -i 's/^MODULES=().*$/MODULES=(tcsrcc-x1e80100 phy-qcom-qmp-pcie phy-qcom-qmp-usb phy-qcom-qmp-usbc phy-qcom-eusb2-repeater phy-qcom-snps-eusb2 phy-qcom-qmp-combo surface-hid surface-aggregator surface-aggregator-registry surface-aggregator-hub)/' /etc/mkinitcpio.conf
		sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="clk_ignore_unused pd_ignore_unused loglevel=7"/' /etc/default/grub

		kernel=$(ls /boot | grep '^vmlinuz')
		kversion="${kernel#vmlinuz-}"
		mkinitcpio -k $kversion -g /boot/initramfs-$kversion.img -v
		grub-install --target=arm64-efi --efi-directory=/mnt/efi --removable
		grub-mkconfig > /boot/grub/grub.cfg
		sed -i '/initrd[[:space:]]*\/boot\/.*\.img/a \	devicetree /boot/dtbs/'$kversion'/qcom/x1e80100-microsoft-denali.dtb' /boot/grub/grub.cfg

		# This process will prevent unmounting after exiting the chroot if it's left dangling
		killall -wv gpg-agent
	EOF
}

function build_kernel {
	if [ ! -f build/boot/vmlinuz* ]; then
		git clone https://github.com/dwhinham/kernel-surface-pro-11 build/linux-sp11 --single-branch --branch wip/x1e80100-6.13-sp11 --depth 1

		cp kernel_config build/linux-sp11/.config

		mkdir -p build/boot build/modules
		export INSTALL_PATH=../boot
		export INSTALL_MOD_PATH=../modules

		make -C build/linux-sp11 -j12
		make -C build/linux-sp11 modules_install
		make -C build/linux-sp11 dtbs_install
		make -C build/linux-sp11 install
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
