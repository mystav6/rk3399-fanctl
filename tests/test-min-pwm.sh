#!/bin/sh
# test-min-pwm.sh - testy výpočtu nových cooling-levels pro --min-pwm
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../scripts" && pwd)
. "${SCRIPT_DIR}/common.sh"

fail=0
export RK3399_FANCTL_LOG_TO_FILE=0

ok()  { printf 'OK:   %s\n' "$1"; }
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
check "nový min > stávající min, střední se zvednou" \
    "0,12,18,255" 30 "0,30,30,255"

check "nový min < stávající min, střední zůstanou" \
    "0,12,18,255" 10 "0,10,18,255"

check "nový min = stávající min, nic se nemění" \
    "0,12,18,255" 12 "0,12,18,255"

check "nový min > všechny střední hodnoty" \
    "0,12,18,255" 200 "0,200,200,255"

# --- Monotónnost ---
check "nový min mezi středními hodnotami - jen nižší se zvednou" \
    "0,12,18,96,255" 30 "0,30,30,96,255"

check "nový min vyšší než všechny střední" \
    "0,12,18,96,255" 100 "0,100,100,100,255"

# --- Hraniční hodnoty ---
check "min_pwm = 0 (vypnutí min PWM)" \
    "0,32,96,255" 0 "0,0,96,255"

check "min_pwm = 255 (vždy na maximum)" \
    "0,32,96,255" 255 "0,255,255,255"

# --- Různý počet úrovní ---
check "pouze 2 úrovně" \
    "0,255" 30 "0,255"

check "5 úrovní" \
    "0,10,20,30,255" 25 "0,25,25,30,255"

# --- První a poslední hodnota se nikdy nemění ---
result=$(apply_min_pwm "0,12,18,255" 30 2>/dev/null)
first=$(printf '%s' "$result" | cut -d, -f1)
last=$(printf '%s' "$result" | awk -F, '{print $NF}')
[ "$first" = "0" ]   && ok "první hodnota zůstane 0" \
                      || nok "první hodnota se změnila: '$first'"
[ "$last" = "255" ]  && ok "poslední hodnota zůstane 255" \
                      || nok "poslední hodnota se změnila: '$last'"

# --- Výsledek ---
if [ "$fail" -eq 0 ]; then
    echo "OK: test-min-pwm.sh"
else
    echo "FAILED: test-min-pwm.sh"
    exit 1
fi
