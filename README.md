# Linux on the Surface Pro 11

These are my notes for getting [Arch Linux ARM](https://archlinuxarm.org) booting on the Microsoft Surface Pro 11.
The [kernel tree can be found here](https://github.com/dwhinham/kernel-surface-pro-11).

> [!NOTE]
> Efforts to upstream a kernel patch set are now underway: https://lore.kernel.org/all/20250714173554.14223-1-daleyo@gmail.com/
> 
> Also see [Issue #12](https://github.com/dwhinham/linux-surface-pro-11/issues/12).

## What's working

> [!WARNING]
> The test model is a Surface Pro 11, OLED version, Wi-Fi only (no 5G), with X1E SoC. If you have a different model (e.g. LCD screen, 5G, X1P CPU) then you're on your own.

| **Feature**               | **Working?** | **Notes**                                                                                                                                                  |
|---------------------------|:------------:|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| NVMe                      |       ✅      |                                                                                                                                                            |
| Graphics                  |       ✅      | 3D acceleration for X1E SoCs only; X1P support is on its way from upstream[^1][^2].                                                                        |
| Backlight                 |       ✅      | Can be adjusted via `/sys/class/backlight/dp_aux_backlight/brightness`                                                                                     |
| USB3                      |   Partially  | USB-C ports are working, but Surface Dock connector is presumably not.                                                                                      |
| USB4/Thunderbolt          |       ❌      | No external display output when using [official USB4 dock](https://learn.microsoft.com/en-us/surface/surface-usb4-dock).                                   |
| USB-C display output      |       ✅      | Working as of 6.15-rc6 (for DP alt mode).                                                                                                                  |
| Wi-Fi                     |       ✅      | Working with a [kernel hack to disable rfkill](https://github.com/dwhinham/kernel-surface-pro-11/commit/fcc769be9eaa9823d55e98a28402104621fa6784).         |
| Bluetooth                 |       ✅      | Requires some `udev` rules to set up a valid MAC address, see [Debian wiki](https://wiki.debian.org/InstallingDebianOn/Thinkpad/X13s#Wi-Fi_and_Bluetooth). |
| Audio                     |       ❌      | Should be similar to Surface Laptop 7.                                                                                                                     |
| Touchscreen               |       ❌      |                                                                                                                                                            |
| Pen                       |       ❌      |                                                                                                                                                            |
| Flex Keyboard             |       ✅      | Only when attached to the Surface Pro; not sure about Bluetooth yet.                                                                                       |
| Suspend/resume            |   Partially  | Lid switch seems to be working when Flex Keyboard covers screen. Resume from sleep can cause machine to hang or produce a black screen.                     |
| Cameras (and status LEDs) |       ❌      |                                                                                                                                                            |

## Arch Linux ARM disk image

A disk image suitable for `dd`'ing to a USB flash drive is [available in the Releases section](https://github.com/dwhinham/linux-surface-pro-11/releases).

This disk image should be enough to get you to a vanilla Arch Linux ARM prompt. [Details here](https://archlinuxarm.org/platforms/armv8/generic).

- Username/password: **alarm**/**alarm**
- Root password: **root**
- For Wi-Fi, `iwd` and `iw` are installed; `iwd` is enabled by default. Run `iwctl` to connect to Wi-Fi; follow the instructions for `iwctl` in the [Arch Linux Wiki](https://wiki.archlinux.org/title/Iwd).
- Alternatively you can use a USB Ethernet adaptor to get the Surface connected to your network. Plug it in before booting; it should pick up an address via DHCP. 
- After connecting to the Internet, run `sudo sp11-grab-fw` and then reboot. This will try to fetch and install proprietary firmware blobs from the [WOA-Project QRD repository](https://github.com/WOA-Project/Qualcomm-Reference-Drivers) ([see below](#firmware-blobs)).
- `sshd` is running as normal with the generic Arch Linux ARM rootfs.

> [!WARNING]
> Without installing the firmware, many hardware components will be broken!

### Installation

Installation to the internal NVMe drive is possible but not for the faint of heart. Don't attempt it unless you know what you're doing!

No detailed instructions for now, but you're basically going to need to do something like:

 - Shrink your Windows partition. Do NOT delete it.
 - Add and format an ext4 partition in the free space.
 - Mount it and copy in the entire contents of the USB drive's Linux root partition.
 - Mount your ESP under the new partition and chroot into the target.
 - Install GRUB, pointing it at the ESP mount point. Hopefully it'll pick up the correct root partition UUID and add a UEFI boot entry.

### Build script

The image is generated by a (very crude) script called [`build.sh`](build.sh). The script only runs on AArch64 Linux machines for now. It will probably break if you try to run it.

The script performs the following:

- Downloads and patches kernel source.
- Builds the kernel, modules and DTBs.
- Downloads the generic AArch64 Arch Linux ARM root filesystem tarball.
- Creates a 4GB disk image and partitions it into a 512MB FAT32 EFI partition and a 3.5GB ext4 root partition.
- Mounts the partitions and extracts the root filesystem.
- Installs our kernel and DTBs into `/boot`.
- Chroots into the rootfs, updates `pacman`, removes the stock kernel and installs firmware and GRUB packages.
- Edits `/etc/mkinitcpio.conf` so that the initramfs contains essential kernel modules for booting (enough to get us USB and the Surface keyboard for debugging).
- Edits `/etc/default/grub` to include some essential kernel command line arguments.
- Creates the initramfs, installs GRUB into `/mnt/efi` and generates the GRUB config.
- Patches the GRUB config scripts so that they add a `devicetree` line that loads our Surface Pro 11 device tree.

## Kernel

The [kernel](https://github.com/dwhinham/kernel-surface-pro-11) is based on [@jhovold's X1E80100 kernel](https://github.com/jhovold/linux), which contains many bleeding-edge patches for machines using Qualcomm X1E SoCs.

### Notable patches

- [drm/msm/dp: work around bogus maximum link rate](https://github.com/dwhinham/kernel-surface-pro-11/commit/f7b7cdf4452ff92d1f3fb407e3f00b2e35b8001b):

  For some reason the DPCD (DisplayPort Configuration Data) contains a zero where a maximum link rate is expected, causing the panel to fail to probe. This patch is an ugly hack which simply hardcodes it to what it should be.

  Some kind of device tree-based override mechanism is probably needed to fix this cleanly, in the same way EDIDs can be overridden[^3].

- [arm64: dts: qcom: add support for Surface Pro 11](https://github.com/dwhinham/kernel-surface-pro-11/commit/525e08bb6ae3e05d6823979e90eb64c501f16851)

  This patch introduces a device tree for the Surface Pro 11. It's nowhere near complete, but it's enough to get started.

- [firmware: qcom: scm: allow QSEECOM on Surface Pro 11](https://github.com/dwhinham/kernel-surface-pro-11/commit/ceda90eb7dcc3c64e845d023ce0a74bc3719ce6e)

  Minor patch to whitelist the Surface Pro 11 and enable access to EFI variables through the QSEECOM driver (useful for setting up bootloaders etc).

- [platform/surface: aggregator_registry: Add Surface Pro 11](https://github.com/dwhinham/kernel-surface-pro-11/commit/9e250e3f9e188e8d72908d2a45e91f6e451863bd)

  This patch enables the Surface Aggregator driver, which gets the Flex Keyboard working. It may be possible to remove this patch and add the SAM into the device tree instead.

- [wifi: ath12k: Add support for disabling rfkill via devicetree](https://github.com/dwhinham/kernel-surface-pro-11/commit/8d317aba05dbd1547383fedeeb3477d0ca546891) and [arm64: dts: qcom: x1e80100-denali: Disable rfkill for wifi0](https://github.com/dwhinham/kernel-surface-pro-11/commit/ee6b71fe054a448b70a73da01081a9306ebe0878)

  Without this, Wi-Fi will be hard-blocked by rfkill. It looks like rfkill is supposed to be disabled according to the ath12k feature flags in the [Surface Pro 11's DSDT](https://github.com/aarch64-laptops/build/blob/master/misc/microsoft-surface-pro-11/acpi/dsdt.dsl) (grep it for `f634f534-6147-11ec-90d6-0242ac120003`, the [UUID of the WCN7850](https://github.com/torvalds/linux/blob/851faa888a523f74f9796c2c1cc7b3f7626f0e25/drivers/net/wireless/ath/ath12k/hw.c#L18-L20)). [A patch to read these feature flags via ACPI](https://lore.kernel.org/all/20250113074810.29729-3-quic_lingbok@quicinc.com/) seems to be making its way upstream, however since ACPI isn't being used here we add a device tree flag that lets us disable it.

### Device tree

The [device tree](https://github.com/dwhinham/kernel-surface-pro-11/blob/wip/x1e80100-6.15-rc6-sp11/arch/arm64/boot/dts/qcom/x1e80100-microsoft-denali.dts) is mostly based on the [Surface Laptop 7](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/x1e80100-microsoft-romulus.dtsi) and [Qualcomm CRD](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/x1e80100-crd.dts) device trees as they share many similarities.

The values for the regulators in the `apps_rsc` section were found by scraping the [DSDT dump](https://github.com/aarch64-laptops/build/blob/master/misc/microsoft-surface-pro-11/acpi/dsdt.dsl) and looking for the sections that contain `PMICVREGVOTE`.

Help is **definitely** needed reviewing and completing this device tree.

### Firmware blobs

Firmware blobs that cannot be distributed here are needed from the stock Windows installation to get certain devices working.

Two scripts are included for firmware extraction:

- [`sp11-grab-fw.sh`](sp11-grab-fw.sh) is installed into `/usr/local/sbin/sp11-grab-fw`. Run `sp11-grab-fw` from Arch Linux, and it will try download firmware from GitHub. Alternatively, install `dislocker-git` from the AUR, then pass the `--win` option to mount your Windows partition and automatically copy the firmware files into the right place. **Note that it will disable the aDSP firmware by appending `.disabled` to the destination file name if it detects that you have booted from USB.**
- [`sp11-grab-fw.bat`](sp11-grab-fw.bat) is included on the disk image's FAT partition which you can run from Windows. This will collect all the firmware into a `firmware` folder on the root of the flash drive.
From Linux, you can then mount the EFI partition and copy the firmware to your system (e.g. `mount /dev/sda1 /mnt/efi; cp -r /mnt/efi/firmware/* /lib/firmware/`). **However, see the note below about aDSP.**

| **Device** |                                                   **Source (Windows)**                                              |                    **Destination (Linux)**                    |
|------------|---------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| GPU        | `C:\Windows\System32\qcdxkmsuc8380.mbn`                                                                             | `/lib/firmware/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn`     |
| aDSP*      | `C:\Windows\System32\DriverStore\FileRepository\surfacepro_ext_adsp8380.inf_arm64_1067fbcaa7f43f02\adsp_dtbs.elf`   | `/lib/firmware/qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn`   |
| aDSP       | `C:\Windows\System32\DriverStore\FileRepository\surfacepro_ext_adsp8380.inf_arm64_1067fbcaa7f43f02\qcadsp8380.mbn`  | `/lib/firmware/qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn` |
| cDSP       | `C:\Windows\System32\DriverStore\FileRepository\qcsubsys_ext_cdsp8380.inf_arm64_9ed31fd1359980a9\cdsp_dtbs.elf`     | `/lib/firmware/qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn`   |
| cDSP       | `C:\Windows\System32\DriverStore\FileRepository\qcsubsys_ext_cdsp8380.inf_arm64_9ed31fd1359980a9\qccdsp8380.mbn`    | `/lib/firmware/qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn` |

> [!WARNING]
> Having the aDSP firmware installed seems to cause USB disconnect/boot failure late on in boot, so it should not be used when booting from USB.

### Thanks

Many thanks to those who helped with my questions on `#aarch64-laptops`!<br />
Additional thanks to @JeromeDeBretagne for assistance with upstream submission and patch contributions.

[^1]: https://lore.kernel.org/dri-devel/20250607-x1p-adreno-v1-0-a8ea80f3b18b@oss.qualcomm.com/T/#u
[^2]: https://www.phoronix.com/news/Adreno-X1-45-GPU-Linux
[^3]: https://oftc.irclog.whitequark.org/aarch64-laptops/2025-01-21#1737478369-1737481210;
