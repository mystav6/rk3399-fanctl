#!/bin/sh
# test-levels.sh - integrační test čtení/zápisu cooling-levels přes dtc
# Pokud dtc není nainstalován, test se přeskočí (ne fail) - je to
# spíš sanity check pro vývojové prostředí než hard requirement CI.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../scripts" && pwd)
. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/dtb-lib.sh"

if ! command_exists dtc; then
    echo "SKIP: test-levels.sh (dtc není nainstalován)"
    exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export RK3399_FANCTL_BACKUP_DIR="$TMP_DIR/backups"
export RK3399_FANCTL_LOG_TO_FILE=0

# Minimální DTS s pwm-fan uzlem pro test
cat > "$TMP_DIR/test.dts" <<'EOF'
/dts-v1/;

/ {
    fan0: pwm-fan {
        compatible = "pwm-fan";
        cooling-levels = <0x00 0x0c 0x12 0xff>;
    };
};
EOF

dtc -I dts -O dtb -o "$TMP_DIR/test.dtb" "$TMP_DIR/test.dts" 2>/dev/null

fail=0

levels=$(dtb_read_cooling_levels "$TMP_DIR/test.dtb")
if [ "$levels" != "0,12,18,255" ]; then
    echo "FAIL: dtb_read_cooling_levels vrátil '$levels', čekáno '0,12,18,255'"
    fail=1
fi

dtb_write_cooling_levels "$TMP_DIR/test.dtb" "0,32,96,255" >/dev/null

new_levels=$(dtb_read_cooling_levels "$TMP_DIR/test.dtb")
if [ "$new_levels" != "0,32,96,255" ]; then
    echo "FAIL: po zápisu jsou levels '$new_levels', čekáno '0,32,96,255'"
    fail=1
fi

if [ ! -f "$TMP_DIR/backups/test.dtb.orig" ]; then
    echo "FAIL: záloha nebyla vytvořena"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK: test-levels.sh"
else
    echo "FAILED: test-levels.sh"
    exit 1
fi
