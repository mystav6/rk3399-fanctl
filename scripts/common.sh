#!/bin/sh
# common.sh - shared functions for logging, colored output and return codes
# POSIX sh compatible (tested with dash and bash)

# --- Return codes ---------------------------------------------------------
# shellcheck disable=SC2034
# Constants are used in sourced scripts (dtb-lib.sh, rk3399-fanctl)
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

# --- Colors (only when output is a terminal) ------------------------------
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

# --- Logging --------------------------------------------------------------
# All log functions write to stderr so stdout stays clean for
# machine-readable output (--show, --monitor etc.)

LOG_FILE="${RK3399_FANCTL_LOG_FILE:-/var/log/rk3399-fanctl.log}"
LOG_TO_FILE="${RK3399_FANCTL_LOG_TO_FILE:-1}"

_log_write_file() {
    # $1 = level, $2 = message
    [ "$LOG_TO_FILE" = "1" ] || return 0
    # Don't fail if log file is not writable (e.g. no root for --show)
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
    # $1 = message, $2 = exit code (optional, default EXIT_INTERNAL_ERROR)
    log_error "$1"
    exit "${2:-$EXIT_INTERNAL_ERROR}"
}

# --- Permission checks ----------------------------------------------------
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This operation requires root privileges (try 'sudo')." "$EXIT_NOT_ROOT"
    fi
}

# --- Helper functions -----------------------------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Compute new cooling-levels for --min-pwm (variant B) ----------------
# $1 = current levels as "0,12,18,255"
# $2 = new minimum PWM value
#
# Logic (variant B - preserve monotonicity):
#   - First value (0 = fan off) is never changed
#   - Second value = new_min (this is the purpose of --min-pwm)
#   - Each middle value: max(original, new_min) - preserves monotonicity
#   - Last value (maximum) is never changed
#   - Works for any number of levels (not just 4)
#
# Examples:
#   apply_min_pwm "0,12,18,255" 30  ->  "0,30,30,255"
#   apply_min_pwm "0,12,18,255" 10  ->  "0,10,18,255"
#   apply_min_pwm "0,12,18,96,255" 30 -> "0,30,30,96,255"
apply_min_pwm() {
    current="$1"
    new_min="$2"

    old_ifs="$IFS"; IFS=,
    # shellcheck disable=SC2086
    set -- $current || true
    IFS="$old_ifs"

    total=$#
    [ "$total" -ge 2 ] || { log_error "apply_min_pwm: need at least 2 levels"; return 1; }

    result=""
    idx=0
    for v in "$@"; do
        idx=$((idx + 1))
        if [ "$idx" -eq 1 ]; then
            # First value (off) - never changed
            new_v="$v"
        elif [ "$idx" -eq "$total" ]; then
            # Last value (maximum) - never changed
            # NOTE: must be checked before idx=2, because with 2 levels
            # the second value is also the last - maximum is always protected
            new_v="$v"
        elif [ "$idx" -eq 2 ]; then
            # Second value = always new_min (purpose of --min-pwm)
            new_v="$new_min"
        else
            # Middle values: max(original, new_min) - preserve monotonicity
            if [ "$v" -lt "$new_min" ]; then
                new_v="$new_min"
            else
                new_v="$v"
            fi
        fi
        result="${result:+${result},}${new_v}"
    done

    printf '%s\n' "$result"
}

# Validate integer in range 0-255 (single PWM value)
is_valid_pwm() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 0 ] && [ "$1" -le 255 ]
}
