# rk3399-fanctl

Open-source utilita pro správu otáček ventilátoru (`pwm-fan`) na deskách
s čipem RK3399 (NanoPC-T4, NanoPi M4, RockPro64, ROCK Pi 4 a další).

Řeší problém příliš agresivních výchozích `cooling-levels` v Device Tree,
které způsobují, že ventilátor běží hlučně i při nízké zátěži (nebo naopak
se vůbec nerozjede při nízkém PWM).

## Stav projektu

🚧 Ve vývoji — fáze 1 (základ projektu).

## Plánované funkce

```
rk3399-fanctl --show
rk3399-fanctl --levels 0,32,96,255
rk3399-fanctl --min-pwm 32
rk3399-fanctl --backup
rk3399-fanctl --restore
rk3399-fanctl --verify
rk3399-fanctl --calibrate
rk3399-fanctl --monitor
```

## Podporované desky

- [x] NanoPC-T4 (RK3399)
- [ ] NanoPi M4
- [ ] RockPro64
- [ ] ROCK Pi 4

## Instalace

```bash
make build
sudo dpkg -i dist/rk3399-fanctl_*.deb
```

## Vývoj

```bash
make lint    # shellcheck nad scripts/
make test    # spustí tests/
make build   # vytvoří .deb balíček
```

## Licence

MIT (viz LICENSE)

## Bezpečnostní poznámka

Tento nástroj upravuje Device Tree Blob (DTB), který je nutný pro nabootování
desky. Vždy se před úpravou vytváří záloha (`--backup`), ale i tak doporučujeme:

1. mít k dispozici sériovou konzoli nebo alternativní způsob přístupu k desce,
2. otestovat `--restore` ještě před tím, než provedete vlastní úpravu,
3. nepoužívat na produkčních systémech bez zálohy celého bootovacího oddílu.
