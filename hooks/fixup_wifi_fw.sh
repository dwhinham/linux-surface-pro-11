#!/bin/sh

# Wi-Fi firmware fixup: extract a compatible board file from board-2.bin and copy it to board.bin.
# ath12k seems to try to load board.bin (single board file) if present, then board-2.bin (bundle of multiple board files and associated device IDs)
# Current linux-firmware package's board-2.bin does not contain a matching device ID for SP11.
# On SP11 ath12k wants: bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255
# This seems close enough: bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255.bin

BDENCODER_URL=https://raw.githubusercontent.com/qca/qca-swiss-army-knife/refs/heads/master/tools/scripts/ath12k/ath12k-bdencoder

tmp=$(mktemp -d)
pushd "$tmp"

cp /lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin* .

# Newer packages have compressed the board-2.bin file
if [ -f board-2.bin.zst ]; then
	zstd -d board-2.bin.zst
fi

python <(curl -sL "$BDENCODER_URL") --extract board-2.bin
mv "bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255.bin" /lib/firmware/ath12k/WCN7850/hw2.0/board.bin

popd
rm -rf "$tmp"
