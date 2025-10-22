#!/bin/bash

set -e

# Fedora Rawhide KDE image settings
FEDORA_BASE_URL=https://kojipkgs.fedoraproject.org/compose/rawhide/latest-Fedora-Rawhide/compose/KDE/aarch64/images
# Default fallback if dynamic fetch fails
FEDORA_IMAGE_NAME_FALLBACK=Fedora-KDE-Desktop-Disk-Rawhide-20251022.n.0.aarch64.raw.xz
DISK_IMAGE_NAME=fedora-linux-arm-sp11.raw.xz

# Mount points for loop devices
LOOP3_MNT=/mnt
LOOP2_MNT=/mnt/root/boot
LOOP1_MNT=/mnt/root/boot/efi

# Surface Pro 11 DTB name (Denali is the codename for Surface Pro 11)
SP11_DTB=qcom/x1e80100-microsoft-denali.dtb

KERNEL_GIT_REPO=https://github.com/dwhinham/kernel-surface-pro-11
KERNEL_GIT_BRANCH=wip/x1e80100-6.17-rc3-sp11

# If "rc" in the branch name then take the config from the ALARM -rc package
if [[ $KERNEL_GIT_BRANCH == *rc* ]]; then
	KERNEL_BASE_CONFIG_URL=https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/linux-aarch64-rc/config
else
	KERNEL_BASE_CONFIG_URL=https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/linux-aarch64/config
fi

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
		curl
		kpartx
		xz
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
	mkdir -p $LOOP1_MNT
}

function detect_latest_fedora_image {
	echo "Detecting latest Fedora image..."
	
	# Try to fetch the directory listing and extract the latest image name
	local latest_image=$(curl -sL "$FEDORA_BASE_URL/" | grep -oP 'Fedora-KDE-Desktop-Disk-Rawhide-[0-9]{8}\.n\.[0-9]+\.aarch64\.raw\.xz' | sort -u | tail -n1)
	
	if [ -n "$latest_image" ]; then
		FEDORA_IMAGE_NAME="$latest_image"
		echo "Found latest image: $FEDORA_IMAGE_NAME"
	else
		FEDORA_IMAGE_NAME="$FEDORA_IMAGE_NAME_FALLBACK"
		echo "Could not detect latest image, using fallback: $FEDORA_IMAGE_NAME"
	fi
}

function get_fedora_image {
	if [ ! -f build/$FEDORA_IMAGE_NAME ]; then
		echo "Downloading Fedora image..."
		curl -fLo build/$FEDORA_IMAGE_NAME "$FEDORA_BASE_URL/$FEDORA_IMAGE_NAME" 2>&1
	fi
	
	# Decompress the image if not already done
	if [ ! -f build/${FEDORA_IMAGE_NAME%.xz} ]; then
		echo "Decompressing Fedora image..."
		xz -d -k build/$FEDORA_IMAGE_NAME
	fi
}

function attach_and_mount {
	raw_image=build/${FEDORA_IMAGE_NAME%.xz}
	
	echo "Attaching image with kpartx..."
	# Capture the output to get the loop device name
	kpartx_output=$(kpartx -av $raw_image)
	echo "$kpartx_output"
	
	# Extract the loop device name (e.g., loop0, loop1, etc.)
	loopdev=$(echo "$kpartx_output" | head -n1 | grep -oP 'loop\d+')
	
	if [ -z "$loopdev" ]; then
		echo "Error: Could not determine loop device"
		exit 1
	fi
	
	echo "Loop device: $loopdev"
	
	# Wait for device nodes to be created
	sleep 2
	
	echo "Mounting partitions..."
	mountpoint -q $LOOP3_MNT || mount /dev/mapper/${loopdev}p3 $LOOP3_MNT
	mountpoint -q $LOOP2_MNT || mount /dev/mapper/${loopdev}p2 $LOOP2_MNT
	mountpoint -q $LOOP1_MNT || mount /dev/mapper/${loopdev}p1 $LOOP1_MNT
	
	echo "Fedora image mounted successfully at /dev/mapper/$loopdev"
}

function unmount_and_detach {
	raw_image=build/${FEDORA_IMAGE_NAME%.xz}
	
	echo "Unmounting partitions..."
	umount $LOOP1_MNT || true
	umount $LOOP2_MNT || true
	umount $LOOP3_MNT || true
	
	echo "Detaching image..."
	kpartx -d $raw_image
	
	echo "Fedora image unmounted and detached"
}

function install_kernel_to_fedora {
	echo "Installing custom kernel to Fedora image..."
	
	# Get kernel version from built kernel
	kernel_version=$(ls build/boot | grep '^vmlinuz-' | sed 's/vmlinuz-//')
	
	if [ -z "$kernel_version" ]; then
		echo "Error: Could not find kernel version"
		exit 1
	fi
	
	echo "Kernel version: $kernel_version"
	
	# Copy kernel
	echo "Copying kernel..."
	cp build/boot/vmlinuz-$kernel_version $LOOP2_MNT/
	cp build/boot/System.map-$kernel_version $LOOP2_MNT/
	cp build/boot/config-$kernel_version $LOOP2_MNT/
	
	# Copy modules
	echo "Copying kernel modules..."
	if [ -d $LOOP3_MNT/root/lib/modules/$kernel_version ]; then
		rm -rf $LOOP3_MNT/lib/root/lib/modules/$kernel_version
	fi
	cp -r build/modules/lib/modules/$kernel_version $LOOP3_MNT/root/lib/modules/
	
	# Copy device tree blobs
	echo "Copying device tree blobs..."
	cp -r build/boot/dtbs/$kernel_version $LOOP2_MNT/dtb-$kernel_version
	
	# Update bootloader entry
	echo "Updating bootloader entry..."
	bootloader_entry=$(ls $LOOP2_MNT/loader/entries/*.conf 2>/dev/null | head -n1)
	
	if [ -n "$bootloader_entry" ]; then
		# Create a new entry for our custom kernel
		custom_entry="${bootloader_entry%.conf}-sp11.conf"
		cp "$bootloader_entry" "$custom_entry"
		
		# Update the entry
		sed -i "s|^linux .*|linux /vmlinuz-$kernel_version|" "$custom_entry"
		sed -i "s|^initrd .*|initrd /initramfs-$kernel_version.img|" "$custom_entry"
		
		# Add or update devicetree line
		if grep -q "^devicetree" "$custom_entry"; then
			sed -i "s|^devicetree .*|devicetree /boot/dtb-$kernel_version/$SP11_DTB|" "$custom_entry"
		else
			echo "devicetree /boot/dtb-$kernel_version/$SP11_DTB" >> "$custom_entry"
		fi
		
		# Add kernel command line arguments if not present
		if ! grep -q "clk_ignore_unused pd_ignore_unused" "$custom_entry"; then
			sed -i 's|^options .*|& clk_ignore_unused pd_ignore_unused|' "$custom_entry"
		fi
		
		echo "Created bootloader entry: $custom_entry"
	else
		echo "Warning: Could not find bootloader entry to update"
	fi
	
	# Copy firmware script to efi partition
	cp sp11-grab-fw.bat $LOOP1_MNT/ 2>/dev/null || true
	
	echo "Kernel installation complete"
}

function build_kernel {
	if [ ! -f build/boot/vmlinuz* ]; then
		git clone $KERNEL_GIT_REPO build/linux-sp11 --single-branch --branch $KERNEL_GIT_BRANCH --depth 1

		# Download base kernel config for Arch Linux ARM
		curl -Lo build/alarm_base_config $KERNEL_BASE_CONFIG_URL

		./build/linux-sp11/scripts/kconfig/merge_config.sh -O build/linux-sp11 -m \
				build/alarm_base_config \
				kernel_config_fragment

		make -C build/linux-sp11 olddefconfig

		mkdir -p build/boot build/modules
		export INSTALL_PATH=../boot
		export INSTALL_MOD_PATH=../modules

		make LOCALVERSION= -C build/linux-sp11 -j$(nproc)
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

detect_latest_fedora_image
get_fedora_image
attach_and_mount
install_kernel_to_fedora
unmount_and_detach

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "Your customized Fedora image is ready at:"
echo "  build/${FEDORA_IMAGE_NAME%.xz}"
echo ""
echo "To write this image to a USB drive or SD card, you can use:"
echo "  xz -c build/${FEDORA_IMAGE_NAME%.xz} | sudo dd of=/dev/sdX bs=4M status=progress"
echo ""
echo "Or compress it first:"
echo "  xz build/${FEDORA_IMAGE_NAME%.xz}"
echo "  # This creates: build/$FEDORA_IMAGE_NAME"
echo ""
echo "Then use arm-image-installer:"
echo "  sudo arm-image-installer --image build/$FEDORA_IMAGE_NAME --media /dev/sdX --resizefs --showboot --args 'clk_ignore_unused pd_ignore_unused'"
echo ""
