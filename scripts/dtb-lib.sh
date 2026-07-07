#!/bin/sh
# dtb-lib.sh - safe direct manipulation of Device Tree Blob (DTB)
# Requires common.sh
#
# STRATEGY:
# Direct modification of /boot/dtb/rockchip/rk3399-nanopc-t4.dtb (or equivalent).
# /boot/dtb is a symlink to /boot/dtb-<version>/ - after a kernel update
# Armbian redirects the symlink to a new directory and our changes are lost.
# Therefore we save state to /var/lib/rk3399-fanctl/state and a kernel hook
# automatically re-applies changes after every kernel update.
#
# SAFETY PRINCIPLES:
# 1. Never write directly - always via temp file + atomic mv
# 2. Always backup the original before first modification
# 3. After compilation verify result size (sanity check)
# 4. If anything fails, the original remains untouched

# --- Configuration (lazy) -------------------------------------------------
_dtb_state_dir() { printf '%s\n' "${RK3399_FANCTL_STATE_DIR:-/var/lib/rk3399-fanctl}"; }
_extlinux_conf()  { printf '%s\n' "${RK3399_FANCTL_EXTLINUX_CONF:-/boot/extlinux/extlinux.conf}"; }
_boot_root()      { printf '%s\n' "${RK3399_FANCTL_BOOT_ROOT:-}"; }

# --- Active DTB detection -------------------------------------------------
dtb_detect_from_extlinux() {
    conf=$(_extlinux_conf)
    [ -r "$conf" ] || return 1

    dtb_path=$(awk '
        /^[[:space:]]*[Ff][Dd][Tt][[:space:]]/ {
            sub(/^[[:space:]]*[Ff][Dd][Tt][[:space:]]+/, "")
            print; exit
        }
    ' "$conf")

    [ -n "$dtb_path" ] || return 1

    boot_root=$(_boot_root)
    case "$dtb_path" in
        /boot/*) dtb_path="${boot_root}${dtb_path}" ;;
        /*)      dtb_path="${boot_root}/boot${dtb_path}" ;;
        *)       dtb_path="${boot_root}/boot/${dtb_path}" ;;
    esac

    [ -f "$dtb_path" ] || return 1
    printf '%s\n' "$dtb_path"
}

dtb_detect_fallback() {
    boot_root=$(_boot_root)
    candidate="${boot_root}/boot/dtb/rockchip/rk3399-nanopc-t4.dtb"
    [ -f "$candidate" ] && printf '%s\n' "$candidate" && return 0
    return 1
}

dtb_resolve_active() {
    if path=$(dtb_detect_from_extlinux); then
        log_debug "DTB from extlinux.conf: $path"
        printf '%s\n' "$path"
        return 0
    fi
    log_warn "Cannot detect DTB from extlinux.conf, trying default path."
    if path=$(dtb_detect_fallback); then
        log_debug "DTB fallback: $path"
        printf '%s\n' "$path"
        return 0
    fi
    return 1
}

# --- Board detection ------------------------------------------------------
board_detect_model() {
    for f in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
        [ -r "$f" ] && tr -d '\0' < "$f" && return 0
    done
    return 1
}

# --- Backup ---------------------------------------------------------------
# Idempotent - backs up only once (preserves the true original, not a backup of backup).
# Backup goes to state dir, not next to DTB - survives kernel updates.
dtb_backup() {
    dtb_path="$1"
    state_dir=$(_dtb_state_dir)
    basefile=$(basename "$dtb_path")
    backup="${state_dir}/backup/${basefile}.orig"

    mkdir -p "${state_dir}/backup" || \
        die "Cannot create backup directory" "$EXIT_BACKUP_FAILED"

    if [ -f "$backup" ]; then
        log_debug "Backup already exists: $backup"
        printf '%s\n' "$backup"
        return 0
    fi

    cp -p "$dtb_path" "$backup" || \
        die "DTB backup failed" "$EXIT_BACKUP_FAILED"

    # Backup metadata
    {
        printf 'source=%s\n' "$dtb_path"
        printf 'timestamp=%s\n' "$(date -Iseconds 2>/dev/null || date)"
        printf 'kernel=%s\n' "$(uname -r 2>/dev/null || echo unknown)"
        printf 'sha256=%s\n' "$(sha256sum "$backup" | awk '{print $1}')"
    } > "${backup}.meta" 2>/dev/null || true

    log_ok "Backup created: $backup"
    printf '%s\n' "$backup"
}

dtb_restore() {
    dtb_path="$1"
    state_dir=$(_dtb_state_dir)
    basefile=$(basename "$dtb_path")
    backup="${state_dir}/backup/${basefile}.orig"

    [ -f "$backup" ] || \
        die "Backup not found: $backup" "$EXIT_NO_BACKUP"

    tmp="${dtb_path}.restore.tmp"
    cp -p "$backup" "$tmp" || die "Failed to copy backup" "$EXIT_RESTORE_FAILED"
    mv -f "$tmp" "$dtb_path" || {
        rm -f "$tmp"
        die "Atomic DTB restore failed" "$EXIT_RESTORE_FAILED"
    }
    log_ok "DTB restored from backup: $dtb_path"
}

# --- Read cooling-levels --------------------------------------------------
dtb_read_cooling_levels() {
    dtb_path="$1"
    [ -f "$dtb_path" ] || die "DTB '$dtb_path' does not exist" "$EXIT_DTB_NOT_FOUND"
    command_exists dtc   || die "'dtc' (device-tree-compiler) is not installed" "$EXIT_INTERNAL_ERROR"

    tmp_dts=$(mktemp /tmp/rk3399-fanctl.XXXXXX.dts) || die "mktemp failed" "$EXIT_INTERNAL_ERROR"
    trap 'rm -f "$tmp_dts"' EXIT INT TERM

    dtc -I dtb -O dts -o "$tmp_dts" "$dtb_path" 2>/dev/null || {
        rm -f "$tmp_dts"; trap - EXIT INT TERM
        die "DTB decompilation failed" "$EXIT_DTC_FAILED"
    }

    raw_hex=$(awk '
        /pwm-fan/ { in_block=1 }
        in_block && /cooling-levels/ {
            match($0, /<[^>]*>/)
            print substr($0, RSTART+1, RLENGTH-2)
            exit
        }
    ' "$tmp_dts")

    rm -f "$tmp_dts"; trap - EXIT INT TERM

    [ -n "$raw_hex" ] || die "cooling-levels not found in DTB" "$EXIT_DTC_FAILED"

    result=""
    for hex in $raw_hex; do
        dec=$((hex))
        result="${result:+${result},}${dec}"
    done
    printf '%s\n' "$result"
}

# --- Validation -----------------------------------------------------------
dtb_validate_levels() {
    levels="$1"
    [ -n "$levels" ] || { log_error "Empty levels list."; return 1; }

    old_ifs="$IFS"; IFS=,
    count=0
    for v in $levels; do
        count=$((count + 1))
        if ! is_valid_pwm "$v"; then
            IFS="$old_ifs"
            log_error "Invalid PWM value '$v'. Allowed range is 0-255."
            return 1
        fi
    done
    IFS="$old_ifs"

    [ "$count" -ge 2 ] || {
        log_error "At least 2 levels are required."
        return 1
    }
    return 0
}

# --- Write cooling-levels -------------------------------------------------
# Safe procedure: decompile -> edit -> recompile to tmp -> sanity
# check -> backup original -> atomic mv to target.
dtb_write_cooling_levels() {
    dtb_path="$1"
    new_levels="$2"

    dtb_validate_levels "$new_levels" || return 1
    command_exists dtc || die "'dtc' is not installed" "$EXIT_INTERNAL_ERROR"

    current=$(dtb_read_cooling_levels "$dtb_path") || return 1
    if [ "$current" = "$new_levels" ]; then
        log_info "Values are identical to current ones. Nothing to do."
        return 2
    fi

    tmp_dts=$(mktemp /tmp/rk3399-fanctl.XXXXXX.dts) || die "mktemp failed" "$EXIT_INTERNAL_ERROR"
    tmp_dtb=$(mktemp /tmp/rk3399-fanctl.XXXXXX.dtb) || { rm -f "$tmp_dts"; die "mktemp failed" "$EXIT_INTERNAL_ERROR"; }
    trap 'rm -f "$tmp_dts" "$tmp_dtb"' EXIT INT TERM

    # Decompile
    dtc -I dtb -O dts -o "$tmp_dts" "$dtb_path" 2>/dev/null || {
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "DTB decompilation failed" "$EXIT_DTC_FAILED"
    }

    # Build new hex string
    new_hex=""
    old_ifs="$IFS"; IFS=,
    for v in $new_levels; do
        hex_v=$(printf '0x%02x' "$v")
        new_hex="${new_hex:+${new_hex} }${hex_v}"
    done
    IFS="$old_ifs"

    # Replace only inside pwm-fan block (awk - safer than global sed)
    awk -v newval="$new_hex" '
        /pwm-fan/ { in_block=1 }
        in_block && /cooling-levels/ {
            sub(/<[^>]*>/, "<" newval ">")
            in_block=0
        }
        { print }
    ' "$tmp_dts" > "${tmp_dts}.new" && mv "${tmp_dts}.new" "$tmp_dts"

    # Recompile
    dtc -I dts -O dtb -o "$tmp_dtb" "$tmp_dts" 2>/dev/null || {
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "New DTB compilation failed - ORIGINAL FILE WAS NOT MODIFIED" "$EXIT_DTC_FAILED"
    }

    # Sanity check - result must not be empty
    # A minimal DTB with one node can be ~100 B (in tests),
    # a real kernel DTB is typically >50 kB. We only check it's not empty.
    new_size=$(wc -c < "$tmp_dtb" 2>/dev/null || echo 0)
    if [ "$new_size" -lt 64 ]; then
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "New DTB is empty or corrupted (${new_size} B) - write cancelled" "$EXIT_VERIFY_FAILED"
    fi

    # Backup original (before first write)
    dtb_backup "$dtb_path" > /dev/null

    # Atomic replacement - preserve original file permissions
    orig_mode=$(stat -c '%a' "$dtb_path" 2>/dev/null || echo '644')
    cp "$tmp_dtb" "${dtb_path}.new" || {
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "Failed to copy new DTB" "$EXIT_DTC_FAILED"
    }
    chmod "$orig_mode" "${dtb_path}.new" || true
    mv -f "${dtb_path}.new" "$dtb_path" || {
        rm -f "$tmp_dts" "$tmp_dtb" "${dtb_path}.new"; trap - EXIT INT TERM
        die "Atomic DTB replacement failed" "$EXIT_DTC_FAILED"
    }

    rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
    log_ok "DTB updated: $current -> $new_levels"
    return 0
}

# --- Verification ---------------------------------------------------------
dtb_verify() {
    dtb_path="$1"
    expected="$2"

    actual=$(dtb_read_cooling_levels "$dtb_path") || {
        log_error "Verification failed: cannot read cooling-levels"
        return 1
    }

    if [ "$actual" != "$expected" ]; then
        log_error "Verification failed: expected='$expected' actual='$actual'"
        return 1
    fi

    log_ok "DTB verified: cooling-levels = $actual"
    return 0
}

# --- State management -----------------------------------------------------
# Save desired cooling-levels to state file.
# Kernel hook reads this state after kernel update and re-applies.
dtb_state_save() {
    levels="$1"
    dtb_path="$2"
    state_dir=$(_dtb_state_dir)
    state_file="${state_dir}/state"

    mkdir -p "$state_dir" || die "Cannot create state directory" "$EXIT_INTERNAL_ERROR"

    {
        printf 'levels=%s\n' "$levels"
        printf 'dtb_path=%s\n' "$dtb_path"
        printf 'applied=%s\n' "$(date -Iseconds 2>/dev/null || date)"
        printf 'kernel=%s\n' "$(uname -r 2>/dev/null || echo unknown)"
    } > "$state_file" || die "Failed to write state file" "$EXIT_INTERNAL_ERROR"

    log_debug "State saved: $state_file"
}

dtb_state_load() {
    state_dir=$(_dtb_state_dir)
    state_file="${state_dir}/state"

    [ -f "$state_file" ] || return 1

    saved_levels=$(awk -F= '/^levels=/{print $2}' "$state_file")
    [ -n "$saved_levels" ] || return 1

    printf '%s\n' "$saved_levels"
}

# --- JSON export for monitoring integration -------------------------------
# Outputs fan status as JSON to stdout.
# Designed to be called from status-export.sh and merged into
# the existing t4-1-status.json / t4-2-status.json.
#
# Output example:
# {
#   "pwm": 32,
#   "pwm_max": 255,
#   "pwm_pct": 13,
#   "cooling_level": 1,
#   "cooling_levels_total": 4,
#   "configured_levels": "0,32,96,255",
#   "state": "on"
# }
fan_export_json() {
    # hwmon number may vary - find the right one
    pwm_file=""
    for f in /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1; do
        [ -r "$f" ] && pwm_file="$f" && break
    done

    # Read current PWM
    pwm=0
    if [ -n "$pwm_file" ] && [ -r "$pwm_file" ]; then
        pwm=$(cat "$pwm_file" 2>/dev/null || echo 0)
    fi

    pwm_max=255
    pwm_pct=$(( (pwm * 100) / pwm_max ))

    # Fan state
    if [ "$pwm" -eq 0 ]; then
        fan_state="off"
    else
        fan_state="on"
    fi

    # Configured levels from saved state
    configured_levels=""
    cooling_level=0
    cooling_levels_total=0

    saved=$(dtb_state_load 2>/dev/null) || saved=""

    if [ -n "$saved" ]; then
        configured_levels="$saved"
        # Count total levels and find active cooling level
        idx=0
        old_ifs="$IFS"; IFS=,
        for v in $saved; do
            cooling_levels_total=$((cooling_levels_total + 1))
            # Active level = highest level whose PWM value <= current pwm
            if [ "$v" -le "$pwm" ]; then
                cooling_level=$idx
            fi
            idx=$((idx + 1))
        done
        IFS="$old_ifs"
    fi

    printf '{\n'
    printf '  "pwm": %s,\n'                  "$pwm"
    printf '  "pwm_max": %s,\n'              "$pwm_max"
    printf '  "pwm_pct": %s,\n'              "$pwm_pct"
    printf '  "cooling_level": %s,\n'        "$cooling_level"
    printf '  "cooling_levels_total": %s,\n' "$cooling_levels_total"
    printf '  "configured_levels": "%s",\n'  "$configured_levels"
    printf '  "state": "%s"\n'               "$fan_state"
    printf '}'
}

dtb_state_clear() {
    state_dir=$(_dtb_state_dir)
    rm -f "${state_dir}/state"
    log_debug "State file removed"
}

# --- Display status -------------------------------------------------------
dtb_show() {
    dtb_path=$(dtb_resolve_active 2>/dev/null) || {
        printf 'Active DTB:      cannot detect\n'
        return 0
    }

    printf 'Active DTB:      %s\n' "$dtb_path"

    # Current cooling-levels in DTB
    if [ ! -r "$dtb_path" ]; then
        printf 'DTB levels:      %s(sudo required to read DTB)%s\n' \
            "$COLOR_YELLOW" "$COLOR_RESET"
    elif levels=$(dtb_read_cooling_levels "$dtb_path" 2>/dev/null); then
        printf 'DTB levels:      %s\n' "$levels"
    else
        printf 'DTB levels:      cannot read\n'
    fi

    # Saved state
    state_dir=$(_dtb_state_dir)
    state_file="${state_dir}/state"
    if [ -f "$state_file" ]; then
        saved=$(awk -F= '/^levels=/{print $2}' "$state_file")
        applied=$(awk -F= '/^applied=/{print $2}' "$state_file")
        kernel=$(awk -F= '/^kernel=/{print $2}' "$state_file")
        printf 'Saved state:     %s (applied: %s, kernel: %s)\n' \
            "$saved" "$applied" "$kernel"
    else
        printf 'Saved state:     none\n'
    fi
}
