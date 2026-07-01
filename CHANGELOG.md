# Changelog

Formát vychází z [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.3.0] - 2026-07-01

### Přidáno
- `--min-pwm` příkaz s variantou B (zachování monotónnosti)
- State management (`/var/lib/rk3399-fanctl/state`)
- Kernel hook (`/etc/kernel/postinst.d/`) pro automatickou re-aplikaci
- `--reapply` příkaz
- CI workflow (GitHub Actions: lint, test, build, release)
- `CONTRIBUTING.md` a PR šablona
- `docs/design.md` a `docs/troubleshooting.md`

### Opraveno
- `--show` bez root zobrazí informativní zprávu místo prázdného řádku
- Zachování původních oprávnění DTB souboru při zápisu
- Zavádějící hláška "Hotovo" při "Nothing to do"




### Plánováno (v1.0)
- Instalace pomocí `.deb`
- Automatická detekce desky (NanoPC-T4)
- Automatická detekce použitého DTB (z `extlinux.conf`)
- Automatická záloha původního DTB
- Obnova původního DTB (`--restore`)
- Zobrazení aktuálních cooling-levels (`--show`)
- Nastavení vlastních hodnot (`--levels`)
- Nastavení minimálního PWM (`--min-pwm`)
- Validace vstupních hodnot
- Verifikace po zápisu (`--verify`)
- Barevný výstup a logování
- Makefile + build skript
- Dokumentace

### Plánováno (v1.1)
- Automatická kalibrace (`--calibrate`)

### Plánováno (v1.2)
- Live monitoring (`--monitor`)

### Plánováno (v2.0)
- Podpora dalších RK3399 desek (NanoPi M4, RockPro64, ROCK Pi 4)
