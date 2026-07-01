# Design a architektonická rozhodnutí

Tento dokument zachycuje klíčová rozhodnutí učiněná během vývoje
`rk3399-fanctl` a důvody proč byly zvoleny konkrétní přístupy.
Slouží jako reference pro budoucí přispěvatele a při rozšiřování
podpory na další desky.

---

## Proč přímá úprava DTB místo Device Tree Overlay

### Co bylo zvažováno

**Varianta A — Device Tree Overlay (.dtbo)**
Minimální overlay soubor patchující pouze uzel `pwm-fan/cooling-levels`.
Originální DTB zůstane nedotčen, overlay se aplikuje u-bootem při startu.

**Varianta B — Přímá úprava DTB** *(zvoleno)*
Dekompilace DTB → textová úprava → rekompilace → atomický zápis zpět.

**Varianta C — systemd service**
Po každém bootu přepíše `/sys/.../pwm1` přímo. Jednoduché, ale řeší
jen okamžitý PWM, ne `cooling-levels` pro thermal daemon (`step_wise`).

### Proč overlay nefungoval

Testování na NanoPC-T4 s Armbian 26.8.0-trunk prokázalo, že U-Boot
flashovaný do eMMC na RK3399 deskách **nepodporuje direktivu `fdtoverlays`
v `extlinux.conf`**. Zařízení se zaseklo na U-Boot obrazovce a nenabootovalo.

Armbian historicky řešil overlaye přes `armbianEnv.txt` + `boot.scr` +
`rockchip-fixup.scr`, ale novější obrazy (26.x) bootují čistě přes
`extlinux.conf` bez těchto pomocných souborů.

### Proč přímá úprava DTB je přijatelná

- DTB soubor je pouze konfigurační data, ne spustitelný kód
- Změna `cooling-levels` je minimálně invazivní (4 bajty v celém souboru)
- Záloha originálu zajišťuje plnou obnovitelnost
- `dtc` (device-tree-compiler) je standardní nástroj dostupný v Armbianu

### Ochrana před aktualizacemi kernelu

Přímá úprava DTB má jednu nevýhodu: po aktualizaci kernelu přes `apt`
Armbian vytvoří nový adresář `dtb-<verze>/` a přesměruje symlink `/boot/dtb`.
Naše úprava na starém DTB zmizí.

Řešení: kernel hook v `/etc/kernel/postinst.d/rk3399-fanctl` automaticky
znovu aplikuje uložené `cooling-levels` po každé aktualizaci kernelu.
State soubor v `/var/lib/rk3399-fanctl/state` přežije aktualizaci kernelu.

---

## Struktura projektu

```
scripts/
├── rk3399-fanctl     ← hlavní CLI vstupní bod
├── common.sh         ← logování, návratové kódy, pomocné funkce
└── dtb-lib.sh        ← veškerá práce s DTB (čtení, zápis, záloha, state)

debian/               ← balíčkovací metadata pro .deb
defaults/             ← konfigurační soubory (apt hook)
docs/                 ← dokumentace
tests/                ← unit testy (POSIX sh, bez externích závislostí)
```

### Proč jsou `common.sh` a `dtb-lib.sh` oddělené

`common.sh` obsahuje funkce které jsou (nebo budou) sdílené napříč více
skripty — logování, validace, návratové kódy. `dtb-lib.sh` je doménově
specifická knihovna. Oddělení umožňuje testovat validaci nezávisle na DTB
logice a zjednodušuje budoucí přidání nových knihoven (`calibrate-lib.sh`,
`monitor-lib.sh`).

---

## Bezpečnostní principy při zápisu DTB

Pořadí operací při `--levels`:

```
1. Validace vstupních hodnot (0-255, min. 2 úrovně)
2. Dekompilace DTB -> dočasný .dts soubor
3. Textová úprava cooling-levels v pwm-fan bloku (awk, ne globální sed)
4. Rekompilace -> dočasný .dtb soubor
5. Sanity check: výsledný .dtb musí být > 512 B
6. Záloha originálu (pouze pokud ještě neexistuje - idempotentní)
7. cp tmp.dtb -> target.dtb.new
8. mv -f target.dtb.new -> target.dtb  (atomický)
9. Verifikace: přečtení a porovnání cooling-levels z nového DTB
10. Uložení stavu do /var/lib/rk3399-fanctl/state
```

Pokud cokoliv selže v krocích 1-8, originální DTB zůstane nedotčen.
Krok 8 (`mv`) je atomický na stejném filesystému — nelze skončit
v mezistavu s poškozeným souborem.

---

## State management

Soubor `/var/lib/rk3399-fanctl/state` obsahuje:

```
levels=0,32,96,255
dtb_path=/boot/dtb/rockchip/rk3399-nanopc-t4.dtb
applied=2026-07-01T13:47:18+02:00
kernel=6.18.37-current-rockchip64
```

Formát `key=value` byl zvolen záměrně — čitelný člověkem, parsovatelný
jednoduchým `awk -F= '/^key=/{print $2}'` bez závislosti na `jq` nebo
jiných nástrojích.

---

## Plánované funkce

### v1.1 — Automatická kalibrace (`--calibrate`)

Postupné zvyšování PWM (5 → 10 → 15 → ...) a detekce nejnižší hodnoty
při které se ventilátor spolehlivě roztočí. Vyžaduje přímý přístup k
`/sys/.../pwm1` a detekci otáček (pokud hardware podporuje tachometr).

### v1.2 — Live monitoring (`--monitor`)

Periodické zobrazení CPU teploty, aktuálního PWM, cooling-level a
thermal governor stavu. Implementováno čtením ze sysfs.

### v2.0 — Podpora dalších RK3399 desek

NanoPi M4, RockPro64, ROCK Pi 4 sdílejí stejný `pwm-fan` uzel v DTB.
Rozšíření bude spočívat v přidání detekce modelu desky (`board_detect_model`
v `common.sh`) a mapování na správný DTB soubor.
