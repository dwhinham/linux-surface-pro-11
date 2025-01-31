# Linux on the Surface Pro 11

These are my patches and notes for getting [Arch Linux ARM](https://archlinuxarm.org) booting on the Microsoft Surface Pro 11.

**Disclaimer:** I have no experience with upstreaming patches, the patch review process, Linux coding conventions, etc. **at all**, so for now I'm just documenting everything here in the hope that more knowledgable people can help!

## What's working

|        **Feature**        | **Working?** |                                                                    **Notes**                                                                   |
|:-------------------------:|:------------:|:----------------------------------------------------------------------------------------------------------------------------------------------:|
| NVMe                      |       ✅      |                                                                                                                                                |
| Graphics                  |       ✅      | Haven't tested 3D acceleration properly yet, but Hyprland works.                                                                               |
| Backlight                 |       ✅      | Can be adjusted via `/sys/class/backlight/dp_aux_backlight/brightness`                                                                         |
| USB                       |   Partially  | USB-C ports are working, but Surface Dock connector is presumably not. USB devices must be inserted before boot or they may not be recognized. |
| USB-C display output      |       ❓      |                                                                                                                                                |
| Wi-Fi                     |       ❌      | ath12k can be probed with the correct firmware in place, but `rfkill` shows that it is hard-blocked (help needed!).                            |
| Bluetooth                 |       ❌      |                                                                                                                                                |
| Audio                     |       ❌      | Should be similar to Surface Laptop 7.                                                                                                         |
| Touchscreen               |       ❌      |                                                                                                                                                |
| Pen                       |       ❌      |                                                                                                                                                |
| Flex Keyboard             |       ✅      | Only when attached to the Surface Pro; no Bluetooth yet.                                                                                       |
| Lid switch/suspend        |       ✅      | Seems to be working.                                                                                                                           |
| Cameras (and status LEDs) |       ❌      |                                                                                                                                                |

## Arch Linux ARM disk image

A disk image suitable for `dd`'ing to a USB flash drive is [available in the Releases section](https://github.com/dwhinham/linux-surface-pro-11/releases).

This disk image should be enough to get you to a vanilla Arch Linux ARM prompt. [Details here](https://archlinuxarm.org/platforms/armv8/generic).

- You'll need a USB Ethernet adaptor to get the Surface connected to your network. Plug it in before booting; it should pick up an address via DHCP.
- `sshd` is running as normal with the generic Arch Linux ARM rootfs.
- Username/password: **alarm**/**alarm**
- Root password: **root**

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
- Patches the GRUB config to add a `devicetree` line that loads our Surface Pro 11 device tree.

## Kernel

The kernel used as a base is [@jhovold's X1E80100 kernel](https://github.com/jhovold/linux) which contains many bleeding-edge patches for machines using Qualcomm X1E SoCs.

### Patches

- [drm/msm/dp: raise maximum pixel clock frequency](kernel_patches/0001-drm-msm-dp-raise-maximum-pixel-clock-frequency.patch)

  The EDID of the Surface's OLED panel requests a higher pixel clock than is currently allowed by the DisplayPort driver, so this patch bumps it up a bit[^1].

- [drm/msm/dp: work around bogus maximum link rate](kernel_patches/0002-drm-msm-dp-work-around-bogus-maximum-link-rate.patch):

  For some reason the DPCD (DisplayPort Configuration Data) contains a zero where a maximum link rate is expected, causing the panel to fail to probe. This patch is an ugly hack which simply hardcodes it to what it should be.

  Some kind of device tree-based override mechanism is probably needed to fix this cleanly, in the same way EDIDs can be overridden[^2].

- [arm64: dts: qcom: add support for Surface Pro 11](kernel_patches/0003-arm64-dts-qcom-add-support-for-Surface-Pro-11.patch)

  This patch introduces a device tree for the Surface Pro 11. It's nowhere near complete, but it's enough to get started.

- [firmware: qcom: scm: allow QSEECOM on Surface Pro 11](kernel_patches/0004-firmware-qcom-scm-allow-QSEECOM-on-Surface-Pro-11.patch)

  Minor patch to whitelist the Surface Pro 11 and enable access to EFI variables through the QSEECOM driver (useful for setting up bootloaders etc).

- [platform/surface: aggregator_registry: Add Surface Pro 11](kernel_patches/0005-platform-surface-aggregator_registry-Add-Surface-Pro.patch)

  This patch enables the Surface Aggregator driver, which gets the Flex Keyboard working.

### Device tree

The device tree is mostly based on the [Surface Laptop 7](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/x1e80100-microsoft-romulus.dtsi) and [Qualcomm CRD](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/x1e80100-crd.dts) device trees as they share many similarities.

The values for the regulators in the `apps_rsc` section were found by scraping the [DSDT dump](https://github.com/aarch64-laptops/build/blob/master/misc/microsoft-surface-pro-11/acpi/dsdt.dsl) and looking for the sections that contain `PMICVREGVOTE`.

Help is **definitely** needed reviewing and completing this device tree.

### Firmware blobs

Firmware blobs that cannot be distributed here are needed from the stock Windows installation to get certain devices working.

A script [`grab_fw.bat`](grab_fw.bat) is included on the disk image's FAT partition which you can run from Windows. This will collect all the firmware into a `firmware` folder on the root of the flash drive.
From Linux, you can then mount the EFI partition and copy the firmware to your system (e.g. `mount /dev/sda1 /mnt/efi; cp -r /mnt/efi/firmware/* /lib/firmware/`). **However, see the note below about aDSP.**

| **Device** |                                                   **Source (Windows)**                                              |                    **Destination (Linux)**                    |
|:----------:|:-------------------------------------------------------------------------------------------------------------------:|:-------------------------------------------------------------:|
| GPU        | `C:\Windows\System32\qcdxkmsuc8380.mbn`                                                                             | `/lib/firmware/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn`     |
| Wi-Fi      | `C:\Windows\System32\DriverStore\FileRepository\qcwlanhmt8380.inf_arm64_b6e9acfd0d644720\wlanfw20.mbn`              | `/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin`                 |
| Wi-Fi      | `C:\Windows\System32\DriverStore\FileRepository\qcwlanhmt8380.inf_arm64_b6e9acfd0d644720\bdwlan_.elf`               | `/lib/firmware/ath12k/WCN7850/hw2.0/board.bin`                |
| Wi-Fi      | `C:\Windows\System32\DriverStore\FileRepository\qcwlanhmt8380.inf_arm64_b6e9acfd0d644720\phy_ucode20.elf`           | `/lib/firmware/ath12k/WCN7850/hw2.0/m3.bin`                   |
| aDSP*       | `C:\Windows\System32\DriverStore\FileRepository\surfacepro_ext_adsp8380.inf_arm64_1067fbcaa7f43f02\adsp_dtbs.elf`  | `/lib/firmware/qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn`   |
| aDSP*       | `C:\Windows\System32\DriverStore\FileRepository\surfacepro_ext_adsp8380.inf_arm64_1067fbcaa7f43f02\qcadsp8380.mbn` | `/lib/firmware/qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn` |
| cDSP       | `C:\Windows\System32\DriverStore\FileRepository\qcsubsys_ext_cdsp8380.inf_arm64_9ed31fd1359980a9\cdsp_dtbs.elf`     | `/lib/firmware/qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn`   |
| cDSP       | `C:\Windows\System32\DriverStore\FileRepository\qcsubsys_ext_cdsp8380.inf_arm64_9ed31fd1359980a9\qccdsp8380.mbn`    | `/lib/firmware/qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn` |

* **Note**: Having the aDSP firmware installed seems to cause USB disconnect/boot failure late on in boot, so I wouldn't use it until this has been debugged.

### Thanks

Many thanks to those who helped with my questions on `#aarch64-laptops`!

[^1]: https://oftc.irclog.whitequark.org/aarch64-laptops/2025-01-21#1737473409-1737472297;
[^2]: https://oftc.irclog.whitequark.org/aarch64-laptops/2025-01-21#1737478369-1737481210;