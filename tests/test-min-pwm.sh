#!/bin/sh
# test-min-pwm.sh - testy výpočtu nových cooling-levels pro --min-pwm
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../scripts" && pwd)
. "${SCRIPT_DIR}/common.sh"

fail=0
export RK3399_FANCTL_LOG_TO_FILE=0

ok()  { printf 'OK:    %s\n' "$1"; }
nok() { printf 'FAIL: %s\n' "$1"; fail=1; }

check() {
    # $1=popis, $2=vstup levels, $3=min_pwm, $4=očekávaný výsledek
    result=$(apply_min_pwm "$2" "$3" 2>/dev/null)
    if [ "$result" = "$4" ]; then
        ok "$1"
    else
        nok "$1: apply_min_pwm '$2' $3 -> '$result' (čekáno '$4')"
    fi
}

# --- Základní chování ---
check "new min > current min, middle values raised" \
    "0,12,18,255" 30 "0,30,30,255"

check "new min < current min, middle values unchanged" \
    "0,12,18,255" 10 "0,10,18,255"

check "new min = current min, nothing changes" \
    "0,12,18,255" 12 "0,12,18,255"

check "new min > all middle values" \
    "0,12,18,255" 200 "0,200,200,255"

# --- Monotónnost ---
check "new min between middle values - only lower ones raised" \
    "0,12,18,96,255" 30 "0,30,30,96,255"

check "new min higher than all middle values" \
    "0,12,18,96,255" 100 "0,100,100,100,255"

# --- Hraniční hodnoty ---
check "min_pwm = 0 (disable minimum PWM)" \
    "0,32,96,255" 0 "0,0,96,255"

check "min_pwm = 255 (always at maximum)" \
    "0,32,96,255" 255 "0,255,255,255"

# --- Různý počet úrovní ---
check "only 2 levels" \
    "0,255" 30 "0,255"

check "5 levels" \
    "0,10,20,30,255" 25 "0,25,25,30,255"

# --- První a poslední hodnota se nikdy nemění ---
result=$(apply_min_pwm "0,12,18,255" 30 2>/dev/null)
first=$(printf '%s' "$result" | cut -d, -f1)
last=$(printf '%s' "$result" | awk -F, '{print $NF}')
[ "$first" = "0" ]   && ok "first value stays 0" \
                      || nok "first value changed: '$first'"
[ "$last" = "255" ]  && ok "last value stays 255" \
                      || nok "last value changed: '$last'"

# --- Výsledek ---
if [ "$fail" -eq 0 ]; then
    echo "OK: test-min-pwm.sh"
else
    echo "FAILED: test-min-pwm.sh"
    exit 1
fi
