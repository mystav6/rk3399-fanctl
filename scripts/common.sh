#!/bin/sh
# common.sh - sdílené funkce pro logování, barevný výstup a návratové kódy
# POSIX sh kompatibilní (testováno s dash i bash)

# --- Návratové kódy ---------------------------------------------------
EXIT_OK=0
EXIT_INVALID_ARGS=1
EXIT_NOT_ROOT=2
EXIT_UNSUPPORTED_BOARD=3
EXIT_DTB_NOT_FOUND=4
EXIT_DTC_FAILED=5
EXIT_VERIFY_FAILED=6
EXIT_BACKUP_FAILED=7
EXIT_RESTORE_FAILED=8
EXIT_NO_BACKUP=9
EXIT_INTERNAL_ERROR=10

# --- Barvy (jen pokud je výstup terminál) ------------------------------
if [ -t 1 ]; then
    COLOR_RED="$(printf '\033[31m')"
    COLOR_GREEN="$(printf '\033[32m')"
    COLOR_YELLOW="$(printf '\033[33m')"
    COLOR_BLUE="$(printf '\033[34m')"
    COLOR_BOLD="$(printf '\033[1m')"
    COLOR_RESET="$(printf '\033[0m')"
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_BOLD=""
    COLOR_RESET=""
fi

# --- Logování -----------------------------------------------------------
# Všechny log funkce píšou na stderr, aby stdout zůstal čistý pro
# strojově zpracovatelný výstup (--show, --monitor apod.)

LOG_FILE="${RK3399_FANCTL_LOG_FILE:-/var/log/rk3399-fanctl.log}"
LOG_TO_FILE="${RK3399_FANCTL_LOG_TO_FILE:-1}"

_log_write_file() {
    # $1 = level, $2 = message
    [ "$LOG_TO_FILE" = "1" ] || return 0
    # Nepadat, pokud log soubor nejde zapsat (např. bez root práv u --show)
    if [ -w "$(dirname "$LOG_FILE")" ] || [ -w "$LOG_FILE" ] 2>/dev/null; then
        printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null
    fi
}

log_info() {
    printf '%s[INFO]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$1" >&2
    _log_write_file "INFO" "$1"
}

log_ok() {
    printf '%s✓%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$1" >&2
    _log_write_file "OK" "$1"
}

log_warn() {
    printf '%s⚠ WARNING:%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1" >&2
    _log_write_file "WARN" "$1"
}

log_error() {
    printf '%s✗ ERROR:%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$1" >&2
    _log_write_file "ERROR" "$1"
}

log_debug() {
    [ "${RK3399_FANCTL_DEBUG:-0}" = "1" ] || return 0
    printf '%s[DEBUG]%s %s\n' "$COLOR_BOLD" "$COLOR_RESET" "$1" >&2
    _log_write_file "DEBUG" "$1"
}

die() {
    # $1 = message, $2 = exit code (volitelné, default EXIT_INTERNAL_ERROR)
    log_error "$1"
    exit "${2:-$EXIT_INTERNAL_ERROR}"
}

# --- Kontroly oprávnění -------------------------------------------------
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Tato operace vyžaduje root oprávnění (zkuste 'sudo')." "$EXIT_NOT_ROOT"
    fi
}

# --- Pomocné funkce -------------------------------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validace celého čísla v rozsahu 0-255 (jedna PWM hodnota)
is_valid_pwm() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 0 ] && [ "$1" -le 255 ]
}
