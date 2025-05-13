#!/bin/sh

patch /etc/grub.d/10_linux << 'EOF2'
--- /etc/grub.d/10_linux.orig	2024-09-12 11:10:30.000000000 +0000
+++ /etc/grub.d/10_linux	2025-02-21 02:15:29.444784121 +0000
@@ -149,6 +149,11 @@
 	echo	'$(echo "$message" | grub_quote)'
 	linux	${rel_dirname}/${basename} root=${linux_root_device_thisversion} rw ${args}
 EOF
+
+  #BEGIN Surface Pro 11
+  echo "	devicetree /boot/dtbs/${version}/qcom/x1e80100-microsoft-denali.dtb" | sed "s/^/$submenu_indentation/"
+  #END Surface Pro 11
+
   if test -n "${initrd}" ; then
     # TRANSLATORS: ramdisk isn't identifier. Should be translated.
     message="$(gettext_printf "Loading initial ramdisk ...")"

EOF2
