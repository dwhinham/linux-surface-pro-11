#!/bin/bash

set -e

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

function create_dirs {
	mkdir -p build/root
}

function clean_build {
	rm -rf build/linux-sp11
	rm -rf build/boot
	rm -rf build/modules
}

function build_kernel {
	git clone https://github.com/dwhinham/kernel-surface-pro-11 build/linux-sp11 --single-branch --branch wip/x1e80100-6.13-sp11 --depth 1

	cp kernel_config build/linux-sp11/.config

	mkdir -p build/boot build/modules
	export INSTALL_PATH=../boot
	export INSTALL_MOD_PATH=../modules

	make -C build/linux-sp11 -j12
	make -C build/linux-sp11 modules_install
	make -C build/linux-sp11 dtbs_install
	make -C build/linux-sp11 install
}

check_root
check_arch

create_dirs
clean_build
build_kernel