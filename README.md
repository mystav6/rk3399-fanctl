# rk3399-fanctl

Open-source utility for managing PWM fan speed (`pwm-fan`) on boards
with the RK3399 chip (NanoPC-T4, NanoPi M4, RockPro64, ROCK Pi 4 and others).

Solves the problem of overly aggressive default `cooling-levels` in the Device Tree,
which cause the fan to run loudly even under low load (or conversely,
fail to start at low PWM values).

## Project status

✅ v1.0.0 — Finished and tested on NanoPC-T4 with Armbian 26.8.x

## Features

```
rk3399-fanctl --show
rk3399-fanctl --levels 0,32,96,255
rk3399-fanctl --min-pwm 32
rk3399-fanctl --backup
rk3399-fanctl --restore
rk3399-fanctl --verify
rk3399-fanctl --reapply
rk3399-fanctl --calibrate 
rk3399-fanctl --monitor   
```

## Supported boards

- [x] NanoPC-T4 (RK3399)
- [ ] NanoPi M4
- [ ] RockPro64
- [ ] ROCK Pi 4

## Installation

```bash
# Install dependency
sudo apt install device-tree-compiler

# Build and install
make build
sudo dpkg -i dist/rk3399-fanctl_*.deb
```

## Quick start

```bash
# Show current status
sudo rk3399-fanctl --show

# Set custom cooling-levels
sudo rk3399-fanctl --levels 0,32,96,255

# Or just set minimum PWM (preserves other levels)
sudo rk3399-fanctl --min-pwm 30

# Restore original DTB
sudo rk3399-fanctl --restore
```

## How it works

`rk3399-fanctl` directly modifies the Device Tree Blob (DTB) in `/boot/dtb/rockchip/`.
The original DTB is always backed up before the first modification.

After a kernel update via `apt`, Armbian redirects the `/boot/dtb` symlink to a new
directory — our changes would be lost. Therefore `rk3399-fanctl` installs a kernel hook
at `/etc/kernel/postinst.d/rk3399-fanctl` that automatically re-applies saved
cooling-levels to the new DTB after every kernel update.

> **Note:** Device Tree Overlay (`fdtoverlays` in extlinux.conf) was evaluated
> but is not supported by U-Boot on RK3399 boards. See [docs/troubleshooting.md](docs/troubleshooting.md).

## Development

```bash
make lint    # shellcheck
make test    # run tests
make build   # build .deb package
```

## License

MIT — see [LICENSE](LICENSE)

## Safety note

This tool modifies the Device Tree Blob (DTB) required for booting.
A backup is always created before modification (`--restore` to recover),
but we still recommend:

1. Having serial console access or an SD card with a working Armbian image
2. Testing `--restore` before making any changes on a critical system
3. See [docs/troubleshooting.md](docs/troubleshooting.md) for recovery procedures
