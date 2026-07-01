#!/bin/sh
# /etc/kernel/postinst.d/rk3399-fanctl
# Spustí se automaticky po instalaci nového kernelu.
# Znovu aplikuje uložené cooling-levels na nový DTB.
#
# Argumenty od kernel hook systému:
#   $1 = verze kernelu (např. "6.18.37-current-rockchip64")
#   $2 = cesta k novému vmlinuz (nepoužíváme)

KERNEL_VERSION="$1"
TOOL="/usr/sbin/rk3399-fanctl"
STATE_FILE="/var/lib/rk3399-fanctl/state"

# Pokud nástroj není nainstalován nebo stav neexistuje, nic neděláme
[ -x "$TOOL" ]       || exit 0
[ -f "$STATE_FILE" ] || exit 0

# Načteme uložené cooling-levels
saved_levels=$(awk -F= '/^levels=/{print $2}' "$STATE_FILE")
[ -n "$saved_levels" ] || exit 0

echo "rk3399-fanctl: Detekována aktualizace kernelu ($KERNEL_VERSION)"
echo "rk3399-fanctl: Znovu aplikuji cooling-levels: $saved_levels"

# Krátká pauza - symlink /boot/dtb se může přesměrovávat ještě po tomto hooku
sleep 1

if "$TOOL" --levels "$saved_levels" --no-state-update 2>&1; then
    echo "rk3399-fanctl: cooling-levels úspěšně aplikovány na nový DTB"
else
    echo "rk3399-fanctl: VAROVÁNÍ - automatická aplikace selhala" >&2
    echo "rk3399-fanctl: Spusťte ručně: sudo rk3399-fanctl --levels $saved_levels" >&2
    # Nevracíme chybu - nechceme blokovat instalaci kernelu
fi

exit 0
