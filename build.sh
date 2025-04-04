#!/bin/bash

set -e

ROOTFS_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
DISK_IMAGE_NAME=arch-linux-arm-sp11.img
DISK_IMAGE_SIZE_MB=4096

KERNEL_GIT_REPO=https://github.com/dwhinham/kernel-surface-pro-11
KERNEL_GIT_BRANCH=wip/x1e80100-6.14-sp11

KERNEL_BASE_CONFIG_URL=https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/linux-aarch64-rc/config

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

	# Install a pacman hook to patch GRUB script and insert SP11 dtb
	cp -r hooks build/root/etc/pacman.d/

	# Chroot into Arch Linux and install some useful tools
	chroot build/root /bin/bash <<-'EOF'
		set -e

		BDENCODER_URL=https://raw.githubusercontent.com/qca/qca-swiss-army-knife/refs/heads/master/tools/scripts/ath12k/ath12k-bdencoder

		mv /etc/resolv.conf{,.bak}
		echo "nameserver 1.1.1.1" > /etc/resolv.conf

		pacman-key --init
		pacman-key --populate archlinuxarm
		pacman -D --asexplicit linux-firmware mkinitcpio
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
			terminus-font

		# Give wheel users (i.e. alarm) no-password sudo access otherwise makepkg won't work
		sed -i 's/^#\s*%wheel\s*ALL=(ALL:ALL)\s*NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

		# Install dislocker from AUR (used for extracting firmware)
		su alarm
			tmp=$(mktemp -d)
			git clone https://aur.archlinux.org/dislocker-git.git "$tmp/dislocker"
			pushd "$tmp/dislocker"

			# Add missing aarch64 architecture
			sed -i "s/arch=(/arch=('aarch64' /" PKGBUILD
			
			makepkg -si --noconfirm
			popd
			rm -rf "$tmp"
		exit

		pacman -Scc --noconfirm

		# Wi-Fi firmware fixup: extract a compatible board file from board-2.bin and copy it to board.bin.
		# ath12k seems to try to load board.bin (single board file) if present, then board-2.bin (bundle of multiple board files and associated device IDs)
		# Current linux-firmware package's board-2.bin does not contain a matching device ID for SP11.
		# On SP11 ath12k wants: bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255
		# This seems close enough: bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255.bin
		tmp=$(mktemp -d)
		pushd "$tmp"
		python <(curl -sL "$BDENCODER_URL") --extract /lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin
		mv "bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255.bin" /lib/firmware/ath12k/WCN7850/hw2.0/board.bin
		popd
		rm -rf "$tmp"

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

		# This process will prevent unmounting after exiting the chroot if it's left dangling
		killall -wv gpg-agent
	EOF
}

function build_kernel {
	if [ ! -f build/boot/vmlinuz* ]; then
		git clone $KERNEL_GIT_REPO build/linux-sp11 --single-branch --branch $KERNEL_GIT_BRANCH --depth 1

		# Download base kernel config for Arch Linux ARM
		curl -Lo build/alarm_base_config $KERNEL_BASE_CONFIG_URL

		./build/linux-sp11/scripts/kconfig/merge_config.sh -O build/linux-sp11 -m \
				build/alarm_base_config \
				build/linux-sp11/arch/arm64/configs/johan_defconfig \
				kernel_config_fragment

		make -C build/linux-sp11 olddefconfig

		mkdir -p build/boot build/modules
		export INSTALL_PATH=../boot
		export INSTALL_MOD_PATH=../modules

		make -C build/linux-sp11 -j12
		make -C build/linux-sp11 modules_install
		make -C build/linux-sp11 dtbs_install
		make -C build/linux-sp11 zinstall
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
