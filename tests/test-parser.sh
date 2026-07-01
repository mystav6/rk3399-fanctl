#!/bin/sh
# test-parser.sh - testy detekce DTB z extlinux.conf
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../scripts" && pwd)
. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/dtb-lib.sh"

fail=0
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Připravíme falešný extlinux.conf + falešný DTB soubor
mkdir -p "$TMP_DIR/boot/dtb/rockchip"
touch "$TMP_DIR/boot/dtb/rockchip/rk3399-nanopc-t4.dtb"

cat > "$TMP_DIR/extlinux.conf" <<EOF
LABEL Armbian
    LINUX /Image
    FDT /dtb/rockchip/rk3399-nanopc-t4.dtb
    INITRD /uInitrd
    APPEND root=/dev/mmcblk0p1
EOF

export RK3399_FANCTL_EXTLINUX_CONF="$TMP_DIR/extlinux.conf"
export RK3399_FANCTL_BOOT_ROOT="$TMP_DIR"

result=$(dtb_detect_from_extlinux) || { echo "FAIL: dtb_detect_from_extlinux selhal"; fail=1; }

expected="$TMP_DIR/boot/dtb/rockchip/rk3399-nanopc-t4.dtb"
if [ "$result" != "$expected" ]; then
    echo "FAIL: neočekávaný výstup: $result (čekáno: $expected)"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK: test-parser.sh"
else
    echo "FAILED: test-parser.sh"
    exit 1
fi
