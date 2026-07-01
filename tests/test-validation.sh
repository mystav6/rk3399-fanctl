#!/bin/sh
# test-validation.sh - testy is_valid_pwm a dtb_validate_levels
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../scripts" && pwd)
. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/dtb-lib.sh"

fail=0

assert_true() {
    if ! "$@" >/dev/null 2>&1; then
        echo "FAIL: expected true: $*"
        fail=1
    fi
}

assert_false() {
    if "$@" >/dev/null 2>&1; then
        echo "FAIL: expected false: $*"
        fail=1
    fi
}

# is_valid_pwm
assert_true  is_valid_pwm 0
assert_true  is_valid_pwm 255
assert_true  is_valid_pwm 32
assert_false is_valid_pwm 256
assert_false is_valid_pwm -1
assert_false is_valid_pwm abc
assert_false is_valid_pwm ""

# dtb_validate_levels
assert_true  dtb_validate_levels "0,32,96,255"
assert_true  dtb_validate_levels "0,255"
assert_false dtb_validate_levels "0,500,999"
assert_false dtb_validate_levels "0"
assert_false dtb_validate_levels ""
assert_false dtb_validate_levels "0,abc,255"

if [ "$fail" -eq 0 ]; then
    echo "OK: test-validation.sh"
else
    echo "FAILED: test-validation.sh"
    exit 1
fi
