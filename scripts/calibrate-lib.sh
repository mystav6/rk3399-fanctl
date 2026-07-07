#!/bin/sh
# calibrate-lib.sh - interactive PWM fan calibration
# Requires common.sh
#
# All user-facing output goes to stderr (>&2) because fan_calibrate()
# is called inside $() substitution in the CLI - stdout is captured
# and used only for returning the recommended levels string.

# --- PWM sysfs helpers ----------------------------------------------------
_pwm_file() {
    for f in /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1; do
        [ -w "$f" ] && printf '%s\n' "$f" && return 0
    done
    return 1
}

_pwm_enable_file() {
    for f in /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1_enable; do
        [ -w "$f" ] && printf '%s\n' "$f" && return 0
    done
    return 1
}

_pwm_set() {
    pwm_file=$(_pwm_file) || die "Cannot find pwm1 sysfs file" "$EXIT_INTERNAL_ERROR"
    printf '%s\n' "$1" > "$pwm_file" || \
        die "Cannot write to $pwm_file (are you root?)" "$EXIT_NOT_ROOT"
}

_pwm_get() {
    pwm_file=$(_pwm_file) || die "Cannot find pwm1 sysfs file" "$EXIT_INTERNAL_ERROR"
    cat "$pwm_file"
}

_pwm_enable_get() {
    f=$(_pwm_enable_file) || return 1
    cat "$f"
}

_pwm_enable_set() {
    f=$(_pwm_enable_file) || die "Cannot find pwm1_enable sysfs file" "$EXIT_INTERNAL_ERROR"
    printf '%s\n' "$1" > "$f" || die "Cannot write to $f" "$EXIT_NOT_ROOT"
}

# --- Restore automatic mode -----------------------------------------------
_calibrate_restore() {
    printf '\n[INFO] Restoring automatic fan control...\n' >&2
    _pwm_enable_set 1 2>/dev/null || true
    printf '%s✓%s Fan control restored to automatic mode.\n' \
        "$COLOR_GREEN" "$COLOR_RESET" >&2
}

# --- Ask user -------------------------------------------------------------
# $1 = PWM value
# Returns: 0=yes (fan running), 1=no (fan stopped), 2=quit
_ask_fan_running() {
    pwm="$1"
    printf '\n%sTesting PWM %s / 255%s\n' \
        "$COLOR_BOLD" "$pwm" "$COLOR_RESET" >&2
    printf 'Listen carefully...\n' >&2
    printf '%sCan you hear the fan running?%s [y/n/q] ' \
        "$COLOR_YELLOW" "$COLOR_RESET" >&2
    read -r answer <&2 || answer="q"
    case "$answer" in
        [Yy]*) return 0 ;;
        [Qq]*) return 2 ;;
        *)     return 1 ;;
    esac
}

# --- Main calibration -----------------------------------------------------
# Outputs recommended levels string on stdout (e.g. "0,30,142,255")
# if user confirms. Otherwise outputs nothing and returns 1.
fan_calibrate() {
    require_root

    _pwm_file >/dev/null 2>&1 || \
        die "PWM fan sysfs not found. Is pwm-fan driver loaded?" "$EXIT_INTERNAL_ERROR"

    printf '\n' >&2
    printf '%s=== Fan Calibration ===%s\n\n' "$COLOR_BOLD" "$COLOR_RESET" >&2
    printf 'This will find the minimum PWM at which your fan starts reliably.\n\n' >&2
    printf '%sWhat will happen:%s\n' "$COLOR_BOLD" "$COLOR_RESET" >&2
    printf '  1. Fan spins at maximum speed briefly\n' >&2
    printf '  2. PWM decreases step by step\n' >&2
    printf '  3. You confirm at each step whether the fan is running\n' >&2
    printf '  4. Recommended cooling-levels will be calculated\n\n' >&2
    printf '%sNote:%s Fan will be loud for a short time. This is normal.\n' \
        "$COLOR_YELLOW" "$COLOR_RESET" >&2
    printf '%sNote:%s Automatic control is always restored on exit.\n\n' \
        "$COLOR_YELLOW" "$COLOR_RESET" >&2
    printf 'Press Enter to start, or Ctrl+C to cancel... ' >&2
    read -r _dummy <&2 || return 1

    # Restore on any exit
    trap '_calibrate_restore' EXIT INT TERM

    # Switch to manual mode
    log_info "Switching to manual fan control..." >&2
    _pwm_enable_set 1

    # Spin up to maximum
    log_info "Spinning fan to maximum (255)..." >&2
    _pwm_set 255
    sleep 3

    printf '\n%sCan you hear the fan at maximum speed?%s [y/n] ' \
        "$COLOR_YELLOW" "$COLOR_RESET" >&2
    read -r answer <&2 || answer="n"
    case "$answer" in
        [Yy]*) : ;;
        *)
            log_warn "Fan not detected at maximum PWM." >&2
            log_warn "Check fan connection and try again." >&2
            trap - EXIT INT TERM
            _calibrate_restore
            return 1
            ;;
    esac

    # Step-down calibration
    printf '\n' >&2
    log_info "Starting step-down calibration..." >&2
    printf 'Answer y=running, n=stopped, q=quit at each step.\n\n' >&2

    test_points="200 150 120 100 80 70 60 55 50 45 40 35 30 25 20 15 10 5"

    last_running=255
    found=0

    for pwm in $test_points; do
        _pwm_set "$pwm"

        if [ "$pwm" -lt 50 ]; then
            sleep 4
        else
            sleep 3
        fi

        _ask_fan_running "$pwm"
        rc=$?

        if [ "$rc" -eq 2 ]; then
            printf '\n' >&2
            log_info "Calibration cancelled." >&2
            trap - EXIT INT TERM
            _calibrate_restore
            return 1
        elif [ "$rc" -eq 0 ]; then
            last_running=$pwm
            found=1
            printf '%s  ✓ Fan running at PWM %s%s\n' \
                "$COLOR_GREEN" "$pwm" "$COLOR_RESET" >&2
        else
            printf '%s  ✗ Fan stopped at PWM %s%s\n' \
                "$COLOR_RED" "$pwm" "$COLOR_RESET" >&2
            break
        fi
    done

    trap - EXIT INT TERM
    _calibrate_restore

    printf '\n' >&2

    if [ "$found" -eq 0 ]; then
        log_warn "Could not determine minimum PWM." >&2
        return 1
    fi

    min_pwm=$last_running

    # Safety margin +4, round to even, cap at 255
    safe_min=$((min_pwm + 4))
    if [ $((safe_min % 2)) -ne 0 ]; then
        safe_min=$((safe_min + 1))
    fi
    [ "$safe_min" -gt 255 ] && safe_min=255

    # Mid point between safe_min and 255
    mid=$(( safe_min + (255 - safe_min) / 2 ))
    recommended_full="0,${safe_min},${mid},255"

    printf '%s=== Calibration Results ===%s\n\n' "$COLOR_BOLD" "$COLOR_RESET" >&2
    printf 'Minimum confirmed PWM:      %s\n'   "$min_pwm" >&2
    printf 'Recommended minimum PWM:    %s %s(+4 safety margin)%s\n' \
        "$safe_min" "$COLOR_YELLOW" "$COLOR_RESET" >&2
    printf 'Recommended cooling-levels: %s%s%s\n\n' \
        "$COLOR_BOLD" "$recommended_full" "$COLOR_RESET" >&2

    printf '%sApply recommended levels (%s)?%s [y/N] ' \
        "$COLOR_YELLOW" "$recommended_full" "$COLOR_RESET" >&2
    read -r answer <&2 || answer="n"

    case "$answer" in
        [Yy]*)
            printf '\n' >&2
            # Output recommended levels on stdout for CLI to capture
            printf '%s\n' "$recommended_full"
            return 0
            ;;
        *)
            printf '\n' >&2
            log_info "Levels not applied. To apply manually:" >&2
            printf '  sudo rk3399-fanctl --levels %s\n\n' \
                "$recommended_full" >&2
            return 1
            ;;
    esac
}
