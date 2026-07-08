#!/bin/sh
# monitor-lib.sh - live fan and temperature monitoring
# Requires common.sh
#
# Displays a continuously updated dashboard showing CPU/GPU temperatures,
# PWM fan status, cooling level and thermal governor.
# Refreshes in-place using ANSI escape codes (no scrolling).
# Press Ctrl+C to exit cleanly.

# --- sysfs paths ----------------------------------------------------------
_mon_cpu_temp_file() {
    printf '%s\n' "/sys/class/thermal/thermal_zone0/temp"
}

_mon_gpu_temp_file() {
    printf '%s\n' "/sys/class/thermal/thermal_zone1/temp"
}

_mon_governor_file() {
    printf '%s\n' "/sys/class/thermal/thermal_zone0/policy"
}

_mon_pwm_file() {
    for f in /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1; do
        [ -r "$f" ] && printf '%s\n' "$f" && return 0
    done
    return 1
}

_mon_cooling_cur_file() {
    # cooling_device2 = pwm-fan (from sysfs discovery)
    for f in /sys/class/thermal/cooling_device*/; do
        type=$(cat "${f}type" 2>/dev/null)
        case "$type" in
            pwm-fan)
                printf '%s\n' "${f}cur_state"
                return 0
                ;;
        esac
    done
    return 1
}

_mon_cooling_max_file() {
    for f in /sys/class/thermal/cooling_device*/; do
        type=$(cat "${f}type" 2>/dev/null)
        case "$type" in
            pwm-fan)
                printf '%s\n' "${f}max_state"
                return 0
                ;;
        esac
    done
    return 1
}

# --- Read helpers ---------------------------------------------------------
_mon_read_temp() {
    # $1 = sysfs temp file, returns temperature in tenths of degree (e.g. 47.6)
    f="$1"
    [ -r "$f" ] || { printf 'N/A'; return; }
    raw=$(cat "$f" 2>/dev/null) || { printf 'N/A'; return; }
    # raw is in millidegrees (e.g. 36875 = 36.875°C)
    deg=$(( raw / 1000 ))
    dec=$(( (raw % 1000) / 100 ))
    printf '%s.%s' "$deg" "$dec"
}

_mon_read_pwm() {
    f=$(_mon_pwm_file 2>/dev/null) || { printf 'N/A'; return; }
    cat "$f" 2>/dev/null || printf 'N/A'
}

_mon_read_governor() {
    f=$(_mon_governor_file)
    [ -r "$f" ] || { printf 'N/A'; return; }
    cat "$f" 2>/dev/null || printf 'N/A'
}

_mon_read_cooling_state() {
    f=$(_mon_cooling_cur_file 2>/dev/null) || { printf 'N/A'; return; }
    cat "$f" 2>/dev/null || printf 'N/A'
}

_mon_read_cooling_max() {
    f=$(_mon_cooling_max_file 2>/dev/null) || { printf '?'; return; }
    cat "$f" 2>/dev/null || printf '?'
}

# --- Temperature color ----------------------------------------------------
# green < 50°C, yellow < 70°C, red >= 70°C
_mon_temp_color() {
    temp_int="${1%%.*}"  # integer part only
    if [ "$temp_int" -lt 50 ]; then
        printf '%s' "$COLOR_GREEN"
    elif [ "$temp_int" -lt 70 ]; then
        printf '%s' "$COLOR_WARN"
    else
        printf '%s' "$COLOR_RED"
    fi
}

# PWM color: green < 40%, yellow < 70%, red >= 70%
_mon_pwm_color() {
    pwm="$1"
    if [ "$pwm" = "N/A" ]; then
        printf '%s' "$COLOR_RESET"
        return
    fi
    pct=$(( (pwm * 100) / 255 ))
    if [ "$pwm" -eq 0 ]; then
        printf '%s' "$COLOR_MUTED"
    elif [ "$pct" -lt 40 ]; then
        printf '%s' "$COLOR_GREEN"
    elif [ "$pct" -lt 70 ]; then
        printf '%s' "$COLOR_WARN"
    else
        printf '%s' "$COLOR_RED"
    fi
}

# --- Bar renderer ---------------------------------------------------------
# $1=value 0-255, $2=width (default 20)
_mon_bar() {
    val="$1"
    width="${2:-20}"
    [ "$val" = "N/A" ] && val=0
    filled=$(( (val * width) / 255 ))
    i=0
    bar=""
    while [ "$i" -lt "$width" ]; do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
        i=$((i + 1))
    done
    printf '%s' "$bar"
}

# --- ANSI helpers ---------------------------------------------------------
# These are defined here because COLOR_WARN and COLOR_MUTED may not be
# in common.sh - we define them locally if needed
_mon_init_colors() {
    if [ -t 1 ]; then
        COLOR_WARN="${COLOR_YELLOW:-$(printf '\033[33m')}"
        COLOR_MUTED="${COLOR_MUTED:-$(printf '\033[2m')}"
        CURSOR_HOME="$(printf '\033[H')"
        CLEAR_SCREEN="$(printf '\033[2J')"
    else
        COLOR_WARN=""
        COLOR_MUTED=""
        CURSOR_HOME=""
        CLEAR_SCREEN=""
    fi
}

# --- Render one frame of the dashboard ------------------------------------
_mon_render() {
    interval="$1"

    cpu_temp=$(_mon_read_temp "$(_mon_cpu_temp_file)")
    gpu_temp=$(_mon_read_temp "$(_mon_gpu_temp_file)")
    pwm=$(_mon_read_pwm)
    governor=$(_mon_read_governor)
    cooling_cur=$(_mon_read_cooling_state)
    cooling_max=$(_mon_read_cooling_max)

    # Configured levels from saved state
    configured=""
    state_file="${RK3399_FANCTL_STATE_DIR:-/var/lib/rk3399-fanctl}/state"
    if [ -f "$state_file" ]; then
        configured=$(awk -F= '/^levels=/{print $2}' "$state_file" 2>/dev/null || true)
    fi

    # PWM percentage
    if [ "$pwm" != "N/A" ] && [ "$pwm" -ge 0 ] 2>/dev/null; then
        pwm_pct=$(( (pwm * 100) / 255 ))
        fan_state="ON"
        [ "$pwm" -eq 0 ] && fan_state="OFF"
    else
        pwm_pct=0
        fan_state="N/A"
    fi

    # Colors
    cpu_color=$(_mon_temp_color "$cpu_temp")
    gpu_color=$(_mon_temp_color "$gpu_temp")
    pwm_color=$(_mon_pwm_color "${pwm:-0}")

    # Timestamp
    now=$(date '+%H:%M:%S')

    # Build dashboard - use printf to stderr so it goes to terminal
    {
        printf '%s\n' "────────────────────────────────────────"
        printf '%s rk3399-fanctl monitor%s · %s · every %ss · Ctrl+C to exit\n' \
            "$COLOR_BOLD" "$COLOR_RESET" "$now" "$interval"
        printf '%s\n' "────────────────────────────────────────"
        printf '\n'

        printf '  %sCPU Temp%s    %s%s °C%s\n' \
            "$COLOR_BOLD" "$COLOR_RESET" \
            "$cpu_color" "$cpu_temp" "$COLOR_RESET"

        printf '  %sGPU Temp%s    %s%s °C%s\n' \
            "$COLOR_BOLD" "$COLOR_RESET" \
            "$gpu_color" "$gpu_temp" "$COLOR_RESET"

        printf '\n'

        printf '  %sPWM%s         %s%s / 255%s  (%s%%)  [%s]\n' \
            "$COLOR_BOLD" "$COLOR_RESET" \
            "$pwm_color" "${pwm:-N/A}" "$COLOR_RESET" \
            "$pwm_pct" "$fan_state"

        printf '  %s             %s%s%s%s\n' \
            "$COLOR_BOLD" \
            "$pwm_color" \
            "$(_mon_bar "${pwm:-0}" 24)" \
            "$COLOR_RESET" \
            "$COLOR_RESET"

        printf '\n'

        printf '  %sCooling lvl%s  %s / %s\n' \
            "$COLOR_BOLD" "$COLOR_RESET" \
            "${cooling_cur:-N/A}" "${cooling_max:-?}"

        printf '  %sGovernor%s    %s\n' \
            "$COLOR_BOLD" "$COLOR_RESET" \
            "$governor"

        if [ -n "$configured" ]; then
            printf '  %sConfigured%s  %s\n' \
                "$COLOR_BOLD" "$COLOR_RESET" \
                "$configured"
        fi

        printf '\n'
        printf '%s\n' "────────────────────────────────────────"
    } >&2
}

# --- Cleanup on exit ------------------------------------------------------
_mon_cleanup() {
    # Show cursor again (we hide it during monitoring)
    printf '\033[?25h' >&2
    printf '\n%sStopped.%s\n' "$COLOR_RESET" "$COLOR_RESET" >&2
}

# --- Main monitor loop ----------------------------------------------------
# $1 = refresh interval in seconds (default 5)
fan_monitor() {
    interval="${1:-5}"

    # Validate interval
    case "$interval" in
        ''|*[!0-9]*) interval=5 ;;
    esac
    [ "$interval" -lt 1 ] && interval=1
    [ "$interval" -gt 3600 ] && interval=3600

    _mon_init_colors

    # Check sysfs availability
    if ! _mon_pwm_file >/dev/null 2>&1; then
        log_error "PWM fan sysfs not found. Is pwm-fan driver loaded?"
        return 1
    fi

    # Setup cleanup
    trap '_mon_cleanup' EXIT INT TERM

    # Hide cursor for cleaner display
    printf '\033[?25l' >&2

    # Clear screen and render first frame
    printf '%s%s' "$CLEAR_SCREEN" "$CURSOR_HOME" >&2
    _mon_render "$interval"

    # Loop
    while true; do
        sleep "$interval"
        # Move cursor back to top and overwrite
        printf '%s' "$CURSOR_HOME" >&2
        _mon_render "$interval"
    done
}
