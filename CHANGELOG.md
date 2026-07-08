# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.5.4] - 2026-07-07

### Added
- `--monitor` interactive fan monitor command
- `docs/design-outputs.md` complete fresh design outputs guide

### Fixed
- Version fixed to 0.5.4 in Makefile and scripts

## [0.5.3] - 2026-07-07

### Added
- `--calibrate` interactive fan calibration command
- `scripts/calibrate-lib.sh` calibration library
- `tests/test-calibrate.sh` unit tests for calibration logic
- `docs/installation.md` complete fresh installation guide

### Fixed
- SC1091 shellcheck directive for calibrate-lib.sh
- SC2034 unused orig_enable variable removed
- Duplicate shellcheck directive removed
- Added -x flag to shellcheck in build.sh
- Version bumped to 0.5.3 in Makefile and scripts

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
