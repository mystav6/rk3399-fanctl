#!/bin/sh
# dtb-lib.sh - bezpečná přímá úprava Device Tree Blob (DTB)
# Vyžaduje common.sh
#
# STRATEGIE:
# Přímá úprava /boot/dtb/rockchip/rk3399-nanopc-t4.dtb (nebo ekvivalentu).
# /boot/dtb je symlink na /boot/dtb-<verze>/ - po aktualizaci kernelu
# Armbian přesměruje symlink na nový adresář a naše úprava zmizí.
# Proto ukládáme stav do /var/lib/rk3399-fanctl/state a kernel hook
# automaticky znovu aplikuje úpravu po každé aktualizaci kernelu.
#
# BEZPEČNOSTNÍ PRINCIPY:
# 1. Nikdy nezapisujeme přímo - vždy přes dočasný soubor + atomický mv
# 2. Před první úpravou vždy zálohujeme originál
# 3. Po kompilaci ověříme velikost výsledku (sanity check)
# 4. Pokud cokoliv selže, originál zůstane nedotčen

# --- Konfigurace (lazy) ---------------------------------------------------
_dtb_state_dir() { printf '%s\n' "${RK3399_FANCTL_STATE_DIR:-/var/lib/rk3399-fanctl}"; }
_extlinux_conf()  { printf '%s\n' "${RK3399_FANCTL_EXTLINUX_CONF:-/boot/extlinux/extlinux.conf}"; }
_boot_root()      { printf '%s\n' "${RK3399_FANCTL_BOOT_ROOT:-}"; }

# --- Detekce aktivního DTB ------------------------------------------------
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
        log_debug "DTB z extlinux.conf: $path"
        printf '%s\n' "$path"
        return 0
    fi
    log_warn "Nelze detekovat DTB z extlinux.conf, zkouším výchozí cestu."
    if path=$(dtb_detect_fallback); then
        log_debug "DTB fallback: $path"
        printf '%s\n' "$path"
        return 0
    fi
    return 1
}

# --- Detekce desky --------------------------------------------------------
board_detect_model() {
    for f in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
        [ -r "$f" ] && tr -d '\0' < "$f" && return 0
    done
    return 1
}

# --- Záloha ---------------------------------------------------------------
# Idempotentní - zálohu uložíme jen jednou (skutečný originál, ne zálohu zálohy).
# Záloha jde do state adresáře, ne vedle DTB - přežije tak aktualizaci kernelu.
dtb_backup() {
    dtb_path="$1"
    state_dir=$(_dtb_state_dir)
    basefile=$(basename "$dtb_path")
    backup="${state_dir}/backup/${basefile}.orig"

    mkdir -p "${state_dir}/backup" || \
        die "Nelze vytvořit adresář pro zálohu" "$EXIT_BACKUP_FAILED"

    if [ -f "$backup" ]; then
        log_debug "Záloha již existuje: $backup"
        printf '%s\n' "$backup"
        return 0
    fi

    cp -p "$dtb_path" "$backup" || \
        die "Záloha DTB selhala" "$EXIT_BACKUP_FAILED"

    # Metadata zálohy
    {
        printf 'source=%s\n' "$dtb_path"
        printf 'timestamp=%s\n' "$(date -Iseconds 2>/dev/null || date)"
        printf 'kernel=%s\n' "$(uname -r 2>/dev/null || echo unknown)"
        printf 'sha256=%s\n' "$(sha256sum "$backup" | awk '{print $1}')"
    } > "${backup}.meta" 2>/dev/null || true

    log_ok "Záloha vytvořena: $backup"
    printf '%s\n' "$backup"
}

dtb_restore() {
    dtb_path="$1"
    state_dir=$(_dtb_state_dir)
    basefile=$(basename "$dtb_path")
    backup="${state_dir}/backup/${basefile}.orig"

    [ -f "$backup" ] || \
        die "Záloha nenalezena: $backup" "$EXIT_NO_BACKUP"

    tmp="${dtb_path}.restore.tmp"
    cp -p "$backup" "$tmp" || die "Kopírování zálohy selhalo" "$EXIT_RESTORE_FAILED"
    mv -f "$tmp" "$dtb_path" || {
        rm -f "$tmp"
        die "Atomická obnova DTB selhala" "$EXIT_RESTORE_FAILED"
    }
    log_ok "DTB obnoven ze zálohy: $dtb_path"
}

# --- Čtení cooling-levels -------------------------------------------------
dtb_read_cooling_levels() {
    dtb_path="$1"
    [ -f "$dtb_path" ] || die "DTB '$dtb_path' neexistuje" "$EXIT_DTB_NOT_FOUND"
    command_exists dtc   || die "'dtc' není nainstalován" "$EXIT_INTERNAL_ERROR"

    tmp_dts=$(mktemp /tmp/rk3399-fanctl.XXXXXX.dts) || die "mktemp selhal" "$EXIT_INTERNAL_ERROR"
    trap 'rm -f "$tmp_dts"' EXIT INT TERM

    dtc -I dtb -O dts -o "$tmp_dts" "$dtb_path" 2>/dev/null || {
        rm -f "$tmp_dts"; trap - EXIT INT TERM
        die "Dekompilace DTB selhala" "$EXIT_DTC_FAILED"
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

    [ -n "$raw_hex" ] || die "cooling-levels nenalezeny v DTB" "$EXIT_DTC_FAILED"

    result=""
    for hex in $raw_hex; do
        dec=$((hex))
        result="${result:+${result},}${dec}"
    done
    printf '%s\n' "$result"
}

# --- Validace -------------------------------------------------------------
dtb_validate_levels() {
    levels="$1"
    [ -n "$levels" ] || { log_error "Prázdný seznam úrovní."; return 1; }

    old_ifs="$IFS"; IFS=,
    count=0
    for v in $levels; do
        count=$((count + 1))
        if ! is_valid_pwm "$v"; then
            IFS="$old_ifs"
            log_error "Neplatná PWM hodnota '$v'. Povolený rozsah je 0-255."
            return 1
        fi
    done
    IFS="$old_ifs"

    [ "$count" -ge 2 ] || {
        log_error "Je potřeba zadat alespoň 2 úrovně."
        return 1
    }
    return 0
}

# --- Zápis cooling-levels -------------------------------------------------
# Bezpečný postup: dekompilace -> úprava -> rekompilace do tmp -> sanity
# check -> záloha originálu -> atomický mv na cíl.
dtb_write_cooling_levels() {
    dtb_path="$1"
    new_levels="$2"

    dtb_validate_levels "$new_levels" || return 1
    command_exists dtc || die "'dtc' není nainstalován" "$EXIT_INTERNAL_ERROR"

    current=$(dtb_read_cooling_levels "$dtb_path") || return 1
    if [ "$current" = "$new_levels" ]; then
        log_info "Hodnoty jsou shodné se stávajícími. Nothing to do."
        return 2
    fi

    tmp_dts=$(mktemp /tmp/rk3399-fanctl.XXXXXX.dts) || die "mktemp selhal" "$EXIT_INTERNAL_ERROR"
    tmp_dtb=$(mktemp /tmp/rk3399-fanctl.XXXXXX.dtb) || { rm -f "$tmp_dts"; die "mktemp selhal" "$EXIT_INTERNAL_ERROR"; }
    trap 'rm -f "$tmp_dts" "$tmp_dtb"' EXIT INT TERM

    # Dekompilace
    dtc -I dtb -O dts -o "$tmp_dts" "$dtb_path" 2>/dev/null || {
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "Dekompilace DTB selhala" "$EXIT_DTC_FAILED"
    }

    # Sestavíme nový hex řetězec
    new_hex=""
    old_ifs="$IFS"; IFS=,
    for v in $new_levels; do
        hex_v=$(printf '0x%02x' "$v")
        new_hex="${new_hex:+${new_hex} }${hex_v}"
    done
    IFS="$old_ifs"

    # Náhrada pouze uvnitř pwm-fan bloku (awk - bezpečnější než globální sed)
    awk -v newval="$new_hex" '
        /pwm-fan/ { in_block=1 }
        in_block && /cooling-levels/ {
            sub(/<[^>]*>/, "<" newval ">")
            in_block=0
        }
        { print }
    ' "$tmp_dts" > "${tmp_dts}.new" && mv "${tmp_dts}.new" "$tmp_dts"

    # Rekompilace
    dtc -I dts -O dtb -o "$tmp_dtb" "$tmp_dts" 2>/dev/null || {
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "Kompilace nového DTB selhala - PŮVODNÍ SOUBOR NEBYL ZMĚNĚN" "$EXIT_DTC_FAILED"
    }

    # Sanity check
    new_size=$(wc -c < "$tmp_dtb" 2>/dev/null || echo 0)
    if [ "$new_size" -lt 512 ]; then
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "Nový DTB je podezřele malý (${new_size} B) - zápis zrušen" "$EXIT_VERIFY_FAILED"
    fi

    # Záloha originálu (před prvním zápisem)
    dtb_backup "$dtb_path" > /dev/null

    # Atomická náhrada - zachováme původní oprávnění souboru
    # cp -p zachová mode/ownership ze zdroje, ale zdrojem je tmp soubor roota.
    # Proto nejdřív zkopírujeme s -p (zachová timestamps), pak nastavíme
    # oprávnění podle originálu pomocí chmod.
    orig_mode=$(stat -c '%a' "$dtb_path" 2>/dev/null || echo '644')
    cp "$tmp_dtb" "${dtb_path}.new" || {
        rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
        die "Kopírování nového DTB selhalo" "$EXIT_DTC_FAILED"
    }
    chmod "$orig_mode" "${dtb_path}.new" || true
    mv -f "${dtb_path}.new" "$dtb_path" || {
        rm -f "$tmp_dts" "$tmp_dtb" "${dtb_path}.new"; trap - EXIT INT TERM
        die "Atomická náhrada DTB selhala" "$EXIT_DTC_FAILED"
    }

    rm -f "$tmp_dts" "$tmp_dtb"; trap - EXIT INT TERM
    log_ok "DTB aktualizován: $current -> $new_levels"
    return 0
}

# --- Verifikace -----------------------------------------------------------
dtb_verify() {
    dtb_path="$1"
    expected="$2"

    actual=$(dtb_read_cooling_levels "$dtb_path") || {
        log_error "Verifikace selhala: nelze přečíst cooling-levels"
        return 1
    }

    if [ "$actual" != "$expected" ]; then
        log_error "Verifikace selhala: expected='$expected' actual='$actual'"
        return 1
    fi

    log_ok "DTB verifikován: cooling-levels = $actual"
    return 0
}

# --- State management -----------------------------------------------------
# Uložíme požadované cooling-levels do state souboru.
# Kernel hook při aktualizaci kernelu tento stav přečte a znovu aplikuje.
dtb_state_save() {
    levels="$1"
    dtb_path="$2"
    state_dir=$(_dtb_state_dir)
    state_file="${state_dir}/state"

    mkdir -p "$state_dir" || die "Nelze vytvořit state adresář" "$EXIT_INTERNAL_ERROR"

    {
        printf 'levels=%s\n' "$levels"
        printf 'dtb_path=%s\n' "$dtb_path"
        printf 'applied=%s\n' "$(date -Iseconds 2>/dev/null || date)"
        printf 'kernel=%s\n' "$(uname -r 2>/dev/null || echo unknown)"
    } > "$state_file" || die "Zápis state souboru selhal" "$EXIT_INTERNAL_ERROR"

    log_debug "Stav uložen: $state_file"
}

dtb_state_load() {
    state_dir=$(_dtb_state_dir)
    state_file="${state_dir}/state"

    [ -f "$state_file" ] || return 1

    # Načteme hodnoty bezpečně - jen known keys
    saved_levels=$(awk -F= '/^levels=/{print $2}' "$state_file")
    [ -n "$saved_levels" ] || return 1

    printf '%s\n' "$saved_levels"
}

dtb_state_clear() {
    state_dir=$(_dtb_state_dir)
    rm -f "${state_dir}/state"
    log_debug "State soubor smazán"
}

# --- Zobrazení stavu ------------------------------------------------------
dtb_show() {
    dtb_path=$(dtb_resolve_active 2>/dev/null) || {
        printf 'Aktivní DTB:     nelze detekovat\n'
        return 0
    }

    printf 'Aktivní DTB:     %s\n' "$dtb_path"

    # Aktuální cooling-levels v DTB
    if [ ! -r "$dtb_path" ]; then
        printf 'DTB levels:      %s(pro čtení DTB je potřeba sudo)%s\n' \
            "$COLOR_YELLOW" "$COLOR_RESET"
    elif levels=$(dtb_read_cooling_levels "$dtb_path" 2>/dev/null); then
        printf 'DTB levels:      %s\n' "$levels"
    else
        printf 'DTB levels:      nelze přečíst\n'
    fi

    # Uložený stav
    state_dir=$(_dtb_state_dir)
    state_file="${state_dir}/state"
    if [ -f "$state_file" ]; then
        saved=$(awk -F= '/^levels=/{print $2}' "$state_file")
        applied=$(awk -F= '/^applied=/{print $2}' "$state_file")
        kernel=$(awk -F= '/^kernel=/{print $2}' "$state_file")
        printf 'Uložený stav:    %s (aplikováno: %s, kernel: %s)\n' \
            "$saved" "$applied" "$kernel"
    else
        printf 'Uložený stav:    žádný\n'
    fi
}
