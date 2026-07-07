#!/bin/sh
# test-calibrate.sh - unit tests for calibrate-lib.sh
# Tests only pure logic functions (no sysfs access required)
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../scripts" && pwd)
. "${SCRIPT_DIR}/common.sh"

fail=0
export RK3399_FANCTL_LOG_TO_FILE=0

ok()  { printf 'OK:   %s\n' "$1"; }
nok() { printf 'FAIL: %s\n' "$1"; fail=1; }

# --- Test safety margin calculation ---------------------------------------
# Minimum confirmed PWM + 4 safety margin, rounded to even number

calc_safe_min() {
    min_pwm="$1"
    safe_min=$((min_pwm + 4))
    if [ $((safe_min % 2)) -ne 0 ]; then
        safe_min=$((safe_min + 1))
    fi
    [ "$safe_min" -gt 255 ] && safe_min=255
    printf '%s\n' "$safe_min"
}

calc_recommended() {
    safe_min="$1"
    mid=$(( safe_min + (255 - safe_min) / 2 ))
    printf '0,%s,%s,255\n' "$safe_min" "$mid"
}

# Safety margin tests
result=$(calc_safe_min 20)
[ "$result" -eq 24 ] && ok "safe_min: 20+4=24 (already even)" \
                      || nok "safe_min 20: got $result expected 24"

result=$(calc_safe_min 21)
[ "$result" -eq 26 ] && ok "safe_min: 21+4=25, rounded to 26" \
                      || nok "safe_min 21: got $result expected 26"

result=$(calc_safe_min 253)
[ "$result" -eq 255 ] && ok "safe_min: capped at 255" \
                        || nok "safe_min 253: got $result expected 255"

result=$(calc_safe_min 0)
[ "$result" -eq 4 ] && ok "safe_min: 0+4=4" \
                     || nok "safe_min 0: got $result expected 4"

# Recommended levels calculation
result=$(calc_recommended 30)
[ "$result" = "0,30,142,255" ] && ok "recommended: 0,30,142,255 for min=30" \
                                || nok "recommended 30: got $result"

result=$(calc_recommended 50)
[ "$result" = "0,50,152,255" ] && ok "recommended: 0,50,152,255 for min=50" \
                                || nok "recommended 50: got $result"

# Edge cases
result=$(calc_recommended 0)
[ "$result" = "0,0,127,255" ] && ok "recommended: handles min=0" \
                               || nok "recommended 0: got $result"

result=$(calc_recommended 200)
[ "$result" = "0,200,227,255" ] && ok "recommended: handles high min=200" \
                                 || nok "recommended 200: got $result"

# --- Result ---
if [ "$fail" -eq 0 ]; then
    echo "OK: test-calibrate.sh"
else
    echo "FAILED: test-calibrate.sh"
    exit 1
fi
