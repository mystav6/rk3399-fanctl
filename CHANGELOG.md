# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.4.0] - 2026-07-07

### Added
- `--export-json` command for monitoring integration
- `fan_export_json()` in dtb-lib.sh reads live PWM from sysfs
- Flask API endpoints for Pi5 (`integration/api-fan-endpoints.py`)
- Fan Control dashboard card (`integration/dashboard-fan-card.html`)
- Updated status-export.sh for T4-1 (`integration/t4-1-status-export.sh`)

### Fixed
- Missing `cmd_reapply()` function header

## [0.3.0] - 2026-07-01

### Added
- `--min-pwm` command with variant B logic (preserves monotonicity)
- State management (`/var/lib/rk3399-fanctl/state`)
- Kernel hook (`/etc/kernel/postinst.d/`) for automatic re-application after kernel updates
- `--reapply` command
- GitHub Actions CI workflow (lint, test, build, release)
- `CONTRIBUTING.md` and PR template
- `docs/design.md` and `docs/troubleshooting.md`

### Fixed
- `--show` without root now displays informative message instead of blank line
- Preserve original DTB file permissions after write (was: 600, now: original mode)
- Misleading "Done" message when "Nothing to do"
- DTB sanity check size reduced from 512B to 64B (was failing on minimal test DTBs)
- shellcheck: SC1007, SC2034, SC1091 warnings resolved

## [0.2.0] - 2026-07-01

### Added
- Initial working implementation
- `--show`, `--levels`, `--restore`, `--verify` commands
- Safe DTB write with atomic mv and backup
- Automatic DTB detection from extlinux.conf
- Colored output and structured logging

### Notes
- DTB overlay approach (fdtoverlays in extlinux.conf) was evaluated and rejected:
  U-Boot on RK3399 boards does not support this directive and the board
  failed to boot. Direct DTB modification was chosen instead.
