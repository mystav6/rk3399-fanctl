# Troubleshooting

Tento dokument zachycuje reálné problémy narazené při vývoji a testování
`rk3399-fanctl` na NanoPC-T4 s Armbian 26.8.x. Může ušetřit hodiny
hledání ostatním uživatelům RK3399.

---

## Zařízení zůstalo viset na U-Boot obrazovce po přidání `fdtoverlays`

### Symptom

Po přidání direktivy `fdtoverlays` do `/boot/extlinux/extlinux.conf` se
zařízení při startu zasekne na U-Boot obrazovce a nenabootuje do systému.

### Příčina

Starší verze U-Bootu na RK3399 (typicky flashované do SPI/eMMC na deskách
jako NanoPC-T4) **nepodporují direktivu `fdtoverlays` v `extlinux.conf`**,
přestože ji novější U-Boot verze podporují.

Armbian na RK3399 používá pro overlay mechanismus vlastní U-Boot skript
(`rockchip-fixup.scr`) spouštěný přes `armbianEnv.txt` — ale novější obrazy
(Armbian 26.x) bootují čistě přes `extlinux.conf` bez `armbianEnv.txt`
a `boot.scr`, takže overlay mechanismus není dostupný vůbec.

Proto `rk3399-fanctl` používá přímou úpravu DTB místo overlay přístupu.

### Obnova systému

Pokud se dostanete do této situace, postupujte takto:

**1. Připravte SD kartu s Armbianem** a nabootujte z ní.

**2. Identifikujte eMMC:**
```bash
lsblk
# eMMC bývá mmcblk2, SD karta mmcblk1
```

**3. Připojte boot partition z eMMC:**
```bash
sudo mkdir -p /mnt/emmc
sudo mount -o rw /dev/mmcblk2p1 /mnt/emmc
# Ověřte že vidíte /boot adresář:
sudo ls /mnt/emmc/boot/
```

> **Poznámka:** Na některých obrazech může být boot partition prázdná na
> první pohled — zkuste `sudo ls /mnt/emmc/boot/` i přesto. Adresář `boot`
> bývá vnořen jako `/mnt/emmc/boot/`.

**4. Odstraňte `fdtoverlays` řádek:**
```bash
sudo sed -i '/fdtoverlays/d' /mnt/emmc/boot/extlinux/extlinux.conf
# Ověřte výsledek:
sudo cat /mnt/emmc/boot/extlinux/extlinux.conf
```

**5. Odpojte a restartujte bez SD karty:**
```bash
sudo umount /mnt/emmc
sudo reboot
```

---

## `--show` nezobrazuje `DTB levels` bez root oprávnění

### Symptom

```
=== rk3399-fanctl stav ===
Aktivní DTB:     /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
Uložený stav:    0,32,96,255 (aplikováno: ...)
```

Chybí řádek `DTB levels: 0,32,96,255`.

### Příčina

DTB soubor v `/boot/dtb/rockchip/` má oprávnění `640` nebo `600` —
čitelný pouze pro root. Běžný uživatel ho nemůže číst, `dtc` selže
a `--show` řádek tiše přeskočí.

### Řešení

```bash
# Zobrazení s root oprávněními
sudo rk3399-fanctl --show

# Nebo nastavte čitelnost DTB pro všechny (volitelné):
sudo chmod 644 /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
```

---

## Kde jsou zálohy a jak je obnovit

### Struktura state adresáře

```
/var/lib/rk3399-fanctl/
├── state                          ← aktuální konfigurace (cooling-levels, timestamp, kernel)
└── backup/
    ├── rk3399-nanopc-t4.dtb.orig  ← originální DTB před první úpravou
    └── rk3399-nanopc-t4.dtb.orig.meta  ← metadata zálohy (sha256, timestamp)
```

### Obnova přes nástroj

```bash
sudo rk3399-fanctl --restore
```

Obnoví originální DTB a smaže uložený stav. Po restartu bude ventilátor
opět řízen výchozími `cooling-levels` z DTB.

### Ruční obnova (pokud nástroj není dostupný)

```bash
sudo cp /var/lib/rk3399-fanctl/backup/rk3399-nanopc-t4.dtb.orig \
        /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
sudo reboot
```

### Ověření zálohy

```bash
# Zobrazení metadat zálohy
cat /var/lib/rk3399-fanctl/backup/rk3399-nanopc-t4.dtb.orig.meta

# Ověření integrity zálohy
sha256sum /var/lib/rk3399-fanctl/backup/rk3399-nanopc-t4.dtb.orig
# Porovnejte s hodnotou sha256= v .meta souboru
```

---

## Co se stane po aktualizaci kernelu

### Symptom

Po `sudo apt upgrade` který nainstaloval nový kernel se ventilátor chová
jako před aplikací `rk3399-fanctl` (příliš hlučný nebo nefunkční při
nízkém PWM).

### Příčina

Armbian při aktualizaci kernelu:
1. Vytvoří nový adresář `/boot/dtb-<nová-verze>/`
2. Přesměruje symlink `/boot/dtb` na nový adresář
3. Naše úprava na starém DTB zmizí — nový DTB má výchozí `cooling-levels`

### Automatická ochrana

`rk3399-fanctl` instaluje hook do `/etc/kernel/postinst.d/rk3399-fanctl`
který se spustí automaticky po instalaci nového kernelu a znovu aplikuje
uložené `cooling-levels` na nový DTB.

Ověřte že hook je nainstalován:
```bash
ls -la /etc/kernel/postinst.d/rk3399-fanctl
```

### Ruční re-aplikace

Pokud automatická re-aplikace selže nebo hook není nainstalován:
```bash
sudo rk3399-fanctl --reapply
```

---

## Ověření funkčnosti ventilátoru za běhu

Aktuální PWM hodnota ventilátoru (bez restartu):

```bash
cat /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1
```

Hodnota odpovídá aktivní `cooling-level` — závisí na aktuální teplotě CPU
a nastavení thermal governoru (`step_wise` v Armbianu).

Ruční nastavení PWM pro testování (dočasné, nepřežije restart):

```bash
echo 128 | sudo tee /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1
```

---

## Podporované desky a testovaný hardware

| Deska       | Armbian verze  | Kernel               | Stav      |
|-------------|----------------|----------------------|-----------|
| NanoPC-T4   | 26.8.0-trunk   | 6.18.37-current-rockchip64 | ✅ Otestováno |
| NanoPi M4   | —              | —                    | 🔲 Netestováno |
| RockPro64   | —              | —                    | 🔲 Netestováno |
| ROCK Pi 4   | —              | —                    | 🔲 Netestováno |

---

## Hlášení chyb

Pokud narazíte na problém který není popsán zde, přiložte prosím výstup:

```bash
sudo rk3399-fanctl --show
uname -r
cat /etc/armbian-release | grep -E "VERSION|BOARD|BRANCH"
cat /boot/extlinux/extlinux.conf
```
