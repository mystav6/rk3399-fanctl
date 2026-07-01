# Design and architectural decisions

This document captures key decisions made during the development of
`rk3399-fanctl` and the reasons why specific approaches were chosen.
It serves as a reference for future contributors and when extending
support to additional boards.

---

## Why direct DTB modification instead of Device Tree Overlay

### Options considered

**Option A — Device Tree Overlay (.dtbo)**
A minimal overlay file patching only the `pwm-fan/cooling-levels` node.
The original DTB remains untouched, the overlay is applied by U-Boot at boot.

**Option B — Direct DTB modification** *(chosen)*
Decompile DTB → text edit → recompile → atomic write back.

**Option C — systemd service**
After each boot, write directly to `/sys/.../pwm1`. Simple, but only solves
immediate PWM, not `cooling-levels` for the thermal daemon (`step_wise`).

### Why overlay did not work

Testing on NanoPC-T4 with Armbian 26.8.0-trunk proved that U-Boot
flashed to eMMC on RK3399 boards **does not support the `fdtoverlays`
directive in `extlinux.conf`**. The board froze at the U-Boot screen
and did not boot.

Armbian historically handled overlays via `armbianEnv.txt` + `boot.scr` +
`rockchip-fixup.scr`, but newer images (26.x) boot purely via
`extlinux.conf` without these helper files.

### Why direct DTB modification is acceptable

- DTB file is configuration data only, not executable code
- Changing `cooling-levels` is minimally invasive (4 bytes in the whole file)
- Original backup ensures full recoverability
- `dtc` (device-tree-compiler) is a standard tool available in Armbian

### Protection against kernel updates

Direct DTB modification has one disadvantage: after a kernel update via `apt`,
Armbian creates a new `dtb-<version>/` directory and redirects the `/boot/dtb`
symlink. Our changes on the old DTB are lost.

Solution: a kernel hook at `/etc/kernel/postinst.d/rk3399-fanctl` automatically
re-applies saved `cooling-levels` after every kernel update.
The state file at `/var/lib/rk3399-fanctl/state` survives the kernel update.

---

## Project structure

```
scripts/
├── rk3399-fanctl     ← main CLI entry point
├── common.sh         ← logging, return codes, helper functions
└── dtb-lib.sh        ← all DTB operations (read, write, backup, state)

debian/               ← packaging metadata for .deb
defaults/             ← configuration files (apt hook)
docs/                 ← documentation
tests/                ← unit tests (POSIX sh, no external dependencies)
```

### Why common.sh and dtb-lib.sh are separate

`common.sh` contains functions shared across multiple scripts — logging,
validation, return codes. `dtb-lib.sh` is a domain-specific library.
The separation allows testing validation independently from DTB logic
and simplifies adding new libraries in the future (`calibrate-lib.sh`,
`monitor-lib.sh`).

---

## Safety principles for DTB writes

Operation order for `--levels`:

```
1.  Validate input values (0-255, min. 2 levels)
2.  Decompile DTB -> temporary .dts file
3.  Text edit cooling-levels in pwm-fan block (awk, not global sed)
4.  Recompile -> temporary .dtb file
5.  Sanity check: result .dtb must be > 64 B
6.  Backup original (only if not yet done - idempotent)
7.  Read original file permissions (stat)
8.  cp tmp.dtb -> target.dtb.new
9.  chmod original_mode target.dtb.new  (preserve permissions)
10. mv -f target.dtb.new -> target.dtb  (atomic)
11. Verify: read and compare cooling-levels from new DTB
12. Save state to /var/lib/rk3399-fanctl/state
```

If anything fails in steps 1-10, the original DTB remains untouched.
Step 10 (`mv`) is atomic on the same filesystem — cannot result in a
corrupted file in an intermediate state.

---

## State management

File `/var/lib/rk3399-fanctl/state` contains:

```
levels=0,32,96,255
dtb_path=/boot/dtb/rockchip/rk3399-nanopc-t4.dtb
applied=2026-07-01T13:47:18+02:00
kernel=6.18.37-current-rockchip64
```

The `key=value` format was chosen intentionally — human-readable, parseable
with simple `awk -F= '/^key=/{print $2}'` without requiring `jq` or other tools.

---

## Planned features

### v1.1 — Automatic calibration (`--calibrate`)

Gradually increase PWM (5 → 10 → 15 → ...) and detect the lowest value
at which the fan reliably starts. Requires direct access to `/sys/.../pwm1`
and RPM detection (if hardware supports a tachometer).

### v1.2 — Live monitoring (`--monitor`)

Periodic display of CPU temperature, current PWM, cooling-level and
thermal governor state. Implemented by reading from sysfs.

### v2.0 — Support for additional RK3399 boards

NanoPi M4, RockPro64, ROCK Pi 4 share the same `pwm-fan` node in the DTB.
Extension will consist of adding board model detection (`board_detect_model`
in `common.sh`) and mapping to the correct DTB file.
