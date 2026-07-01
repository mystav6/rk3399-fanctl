# Jak přispět do projektu

Děkujeme za zájem o přispění do `rk3399-fanctl`. Tento dokument popisuje
jak projekt sestavit, otestovat a odeslat Pull Request.

## Požadavky pro vývoj

```bash
sudo apt install device-tree-compiler shellcheck dpkg-dev
```

## Sestavení a testování

```bash
# Klonování
git clone https://github.com/<tvůj-nick>/rk3399-fanctl.git
cd rk3399-fanctl

# Lint (shellcheck)
make lint

# Testy
make test

# Sestavení .deb
make build
```

## Struktura projektu

```
scripts/
├── rk3399-fanctl     hlavní CLI vstupní bod
├── common.sh         logování, návratové kódy, pomocné funkce
├── dtb-lib.sh        práce s DTB (čtení, zápis, záloha, state)
└── kernel-hook.sh    hook pro automatickou re-aplikaci po aktualizaci kernelu

tests/
├── test-parser.sh    testy detekce DTB z extlinux.conf
├── test-validation.sh testy validace PWM hodnot
└── test-levels.sh    integrační test čtení/zápisu cooling-levels (vyžaduje dtc)

docs/
├── design.md         architektonická rozhodnutí
├── troubleshooting.md řešení problémů
└── internals.md      (plánováno)
```

## Pravidla pro kód

- **POSIX sh** — bez bash-specific syntaxe (žádné `[[`, `(( ))`, `$'...'`)
- **shellcheck čistý** — `make lint` musí projít bez varování
- **Návratové kódy** — používejte konstanty z `common.sh` (`EXIT_OK`, `EXIT_INVALID_ARGS` atd.)
- **Logování** — pouze přes funkce z `common.sh` (`log_info`, `log_ok`, `log_error` atd.)
- **Atomické zápisy** — jakýkoliv zápis souboru přes dočasný soubor + `mv`
- **Komentáře** — každá veřejná funkce má komentář popisující co dělá a co vrací

## Přidání podpory pro novou desku

1. Ověřte že deska používá `pwm-fan` uzel s `cooling-levels` v DTB:
   ```bash
   dtc -I dtb -O dts /boot/dtb/rockchip/<vaše-deska>.dtb 2>/dev/null \
       | grep -A5 "pwm-fan"
   ```

2. Přidejte detekci modelu do `dtb-lib.sh` (`board_detect_model`)

3. Přidejte desku do tabulky v `docs/troubleshooting.md`

4. Otestujte všechny příkazy na reálném hardware a popište výsledky v PR

## Verzování

Projekt používá [Semantic Versioning](https://semver.org/):

- `0.x.y` — dokud není stabilní API (aktuální stav)
- `MAJOR.MINOR.PATCH` — po dosažení v1.0.0

Release se vytvoří pushnutím tagu:
```bash
git tag v0.3.0
git push origin v0.3.0
```

GitHub Actions automaticky sestaví `.deb` a vytvoří Release.

## Hlášení chyb

Při hlášení chyby prosím přiložte:

```bash
sudo rk3399-fanctl --show
uname -r
cat /etc/armbian-release | grep -E "VERSION|BOARD|BRANCH"
sudo cat /boot/extlinux/extlinux.conf
```
