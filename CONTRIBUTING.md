# Contributing

Thank you for your interest in contributing to `rk3399-fanctl`.
This document describes how to build, test, and submit a Pull Request.

## Development requirements

```bash
sudo apt install device-tree-compiler shellcheck dpkg-dev
```

## Build and test

```bash
# Clone
git clone https://github.com/<your-nick>/rk3399-fanctl.git
cd rk3399-fanctl

# Lint (shellcheck)
make lint

# Tests
make test

# Build .deb
make build
```

## Project structure

```
scripts/
├── rk3399-fanctl      main CLI entry point
├── common.sh          logging, return codes, helper functions
├── dtb-lib.sh         DTB operations (read, write, backup, state)
└── kernel-hook.sh     hook for automatic re-application after kernel updates

tests/
├── test-parser.sh     DTB detection from extlinux.conf
├── test-validation.sh PWM value validation
├── test-min-pwm.sh    --min-pwm logic (variant B)
└── test-levels.sh     integration test for read/write cooling-levels (requires dtc)

docs/
├── design.md          architectural decisions
├── troubleshooting.md troubleshooting guide
└── internals.md       (planned)
```

## Code style

- **POSIX sh** — no bash-specific syntax (no `[[`, `(( ))`, `$'...'`)
- **shellcheck clean** — `make lint` must pass without warnings
- **Return codes** — use constants from `common.sh` (`EXIT_OK`, `EXIT_INVALID_ARGS` etc.)
- **Logging** — only via functions from `common.sh` (`log_info`, `log_ok`, `log_error` etc.)
- **Atomic writes** — any file write via temp file + `mv`
- **Comments** — every public function has a comment describing what it does and what it returns

## Adding support for a new board

1. Verify the board uses a `pwm-fan` node with `cooling-levels` in the DTB:
   ```bash
   dtc -I dtb -O dts /boot/dtb/rockchip/<your-board>.dtb 2>/dev/null \
       | grep -A5 "pwm-fan"
   ```

2. Add model detection to `dtb-lib.sh` (`board_detect_model`)

3. Add the board to the table in `docs/troubleshooting.md`

4. Test all commands on real hardware and describe results in the PR

## Versioning

The project uses [Semantic Versioning](https://semver.org/):

- `0.x.y` — while API is not yet stable (current state)
- `MAJOR.MINOR.PATCH` — after reaching v1.0.0

Create a release by pushing a tag:
```bash
git tag v0.4.0
git push origin v0.4.0
```

GitHub Actions will automatically build the `.deb` and create a Release.

## Reporting bugs

When reporting a bug please include:

```bash
sudo rk3399-fanctl --show
uname -r
cat /etc/armbian-release | grep -E "VERSION|BOARD|BRANCH"
sudo cat /boot/extlinux/extlinux.conf
```
