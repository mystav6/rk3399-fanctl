# rk3399-fanctl — Output Design Reference

This document describes all visual outputs, data formats and design elements
of `rk3399-fanctl`. It is intended for integration with other projects
(dashboards, monitoring systems) that need to display or consume fan control data.

---

## Visual design principles

- **Font:** Monospace terminal font (IBM Plex Mono or system default)
- **Color scheme:** Dark background terminal (black/dark gray)
- **Output channels:** All user-facing output goes to **stderr**, stdout is reserved for machine-readable data (`--export-json`, calibration result)
- **Color triggers:** Colors are only applied when output is a terminal (`[ -t 1 ]`), never in pipes or redirects

### Color palette

| Role | ANSI | Usage |
|---|---|---|
| Green `\033[32m` | OK / fan running / low temp | ✓ confirmations, temp < 50°C, PWM < 40% |
| Yellow `\033[33m` | Warning / medium | ⚠ warnings, temp 50–70°C, PWM 40–70% |
| Red `\033[31m` | Error / critical | ✗ errors, temp ≥ 70°C, PWM ≥ 70% |
| Blue `\033[34m` | Info | [INFO] messages |
| Bold `\033[1m` | Labels / headers | Section titles, dashboard labels |
| Dim/muted | Fan OFF state | PWM = 0 |
| Reset `\033[0m` | Reset | After every colored segment |

---

## CLI output formats

### `--show`

```
=== rk3399-fanctl status ===

Active DTB:      /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
DTB levels:      0,32,96,255
Saved state:     0,32,96,255 (applied: 2026-07-01T13:47:18+02:00, kernel: 6.18.37-current-rockchip64)
```

- **Active DTB** — absolute path to the DTB file currently used at boot
- **DTB levels** — raw cooling-levels read from the DTB binary (requires sudo)
- **Saved state** — levels stored in `/var/lib/rk3399-fanctl/state` with timestamp and kernel version
- Without sudo: `DTB levels: (sudo required to read DTB)` in yellow

---

### `--levels` / `--min-pwm`

```
[INFO] Setting cooling-levels: 0,32,96,255
[INFO] Target DTB: /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
✓ Backup created: /var/lib/rk3399-fanctl/backup/rk3399-nanopc-t4.dtb.orig
✓ DTB updated: 0,12,18,255 -> 0,32,96,255
✓ DTB verified: cooling-levels = 0,32,96,255

✓ Done. New cooling-levels are immediately active.
[INFO] Will be automatically re-applied after kernel updates.
```

- Green `✓` for each successful step
- Arrow notation `old -> new` for DTB changes
- "Nothing to do" variant when values are already set:

```
[INFO] cooling-levels 0,32,96,255 are already set.
[INFO] State saved for automatic re-application after kernel update.
```

---

### `--verify`

Success:
```
✓ DTB verified: cooling-levels = 0,32,96,255
```

Failure:
```
✗ ERROR: Verification failed: expected='0,32,96,255' actual='0,12,18,255'
```

---

### `--calibrate`

```
=== Fan Calibration ===

This will find the minimum PWM at which your fan starts reliably.

What will happen:
  1. Fan spins at maximum speed briefly
  2. PWM decreases step by step
  3. You confirm at each step whether the fan is running
  4. Recommended cooling-levels will be calculated

Note: Fan will be loud for a short time. This is normal.
Note: Automatic control is always restored on exit.

Press Enter to start, or Ctrl+C to cancel...
[INFO] Switching to manual fan control...
[INFO] Spinning fan to maximum (255)...

Can you hear the fan at maximum speed? [y/n] y
[INFO] Starting step-down calibration...
Answer y=running, n=stopped, q=quit at each step.

Testing PWM 200 / 255
Listen carefully...
Can you hear the fan running? [y/n/q] y
  ✓ Fan running at PWM 200

...

Testing PWM 5 / 255
Listen carefully...
Can you hear the fan running? [y/n/q] n
  ✗ Fan stopped at PWM 5

[INFO] Restoring automatic fan control...
✓ Fan control restored to automatic mode.

=== Calibration Results ===

Minimum confirmed PWM:      10
Recommended minimum PWM:    14  (+4 safety margin)
Recommended cooling-levels: 0,14,134,255

Apply recommended levels (0,14,134,255)? [y/N]
```

**Safety margin logic:**
- `safe_min = detected_min + 4`
- Round up to nearest even number
- Cap at 255
- Mid point: `safe_min + (255 - safe_min) / 2`
- Result format: `0,safe_min,mid,255`

---

### `--monitor`

Live dashboard, refreshes in-place using ANSI cursor control:

```
────────────────────────────────────────
 rk3399-fanctl monitor · 01:54:21 · every 5s · Ctrl+C to exit
────────────────────────────────────────

  CPU Temp    36.8 °C
  GPU Temp    37.5 °C

  PWM         30 / 255  (11%)  [ON]
               █░░░░░░░░░░░░░░░░░░░░░░░

  Cooling lvl  0 / 3
  Governor    step_wise
  Configured  0,14,134,255

────────────────────────────────────────
```

**Layout:**
- Header line with tool name, current time, interval, exit hint
- Top/bottom separator: `────────────────────────────────────────` (40 chars)
- 2-space indent on all data rows
- Label column: fixed width, bold
- Value column: colored by severity

**Temperature colors:**
- Green: < 50°C
- Yellow: 50–69°C
- Red: ≥ 70°C

**PWM bar:**
- Width: 24 characters
- Filled: `█`, empty: `░`
- Color matches PWM severity (green/yellow/red/dim for OFF)
- PWM color thresholds: green < 40%, yellow 40–69%, red ≥ 70%, dim = OFF

**Fan state:**
- `[ON]` — PWM > 0
- `[OFF]` — PWM = 0 (shown in muted/dim color)

**Cooling level:**
- Format: `current / max_state` (0-indexed, max_state from sysfs)
- `max_state = 3` means 4 levels (0,1,2,3)

**Configured:**
- Shows saved cooling-levels from `/var/lib/rk3399-fanctl/state`
- Omitted if state file does not exist (tool not yet configured)

**Usage:**
```bash
sudo rk3399-fanctl --monitor              # default 5s refresh
sudo rk3399-fanctl --monitor 10           # 10s refresh
sudo rk3399-fanctl --monitor --interval 30  # explicit syntax
```

---

## Machine-readable output

### `--export-json`

Outputs to **stdout**, suitable for piping and monitoring integration:

```json
{
  "pwm": 32,
  "pwm_max": 255,
  "pwm_pct": 13,
  "cooling_level": 1,
  "cooling_levels_total": 4,
  "configured_levels": "0,32,96,255",
  "state": "on"
}
```

**Fields:**

| Field | Type | Description |
|---|---|---|
| `pwm` | integer | Current PWM value (0–255) |
| `pwm_max` | integer | Maximum PWM (always 255) |
| `pwm_pct` | integer | PWM as percentage (0–100) |
| `cooling_level` | integer | Active cooling level index (0-based) |
| `cooling_levels_total` | integer | Total number of configured levels |
| `configured_levels` | string | Comma-separated cooling-levels from state |
| `state` | string | `"on"` if PWM > 0, `"off"` if PWM = 0 |

**Sources:**
- `pwm` — read from `/sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1`
- `configured_levels`, `cooling_levels_total`, `cooling_level` — from `/var/lib/rk3399-fanctl/state`
- `state` — derived from `pwm`

**Integration example (Pi5 Flask API):**
```python
# GET /api/fan/status/t41
# Calls: ssh mysta@T4-1 "sudo rk3399-fanctl --export-json"
# Returns:
{
    "ok": true,
    "device": "t41",
    "fan": { ...fields above... },
    "timestamp": 1751234567
}
```

---

## State file format

`/var/lib/rk3399-fanctl/state` — plain key=value, human-readable:

```
levels=0,32,96,255
dtb_path=/boot/dtb/rockchip/rk3399-nanopc-t4.dtb
applied=2026-07-01T13:47:18+02:00
kernel=6.18.37-current-rockchip64
```

Parse with: `awk -F= '/^levels=/{print $2}' /var/lib/rk3399-fanctl/state`

---

## Log format

`/var/log/rk3399-fanctl.log`:

```
2026-07-01 13:47:18 [INFO] Setting cooling-levels: 0,32,96,255
2026-07-01 13:47:18 [OK] DTB updated: 0,12,18,255 -> 0,32,96,255
2026-07-01 13:47:19 [OK] DTB verified: cooling-levels = 0,32,96,255
```

Format: `YYYY-MM-DD HH:MM:SS [LEVEL] message`
Levels: `INFO`, `OK`, `WARN`, `ERROR`, `DEBUG`

---

## Return codes

| Code | Constant | Meaning |
|---|---|---|
| 0 | EXIT_OK | Success |
| 1 | EXIT_INVALID_ARGS | Invalid arguments or unsupported command |
| 2 | EXIT_NOT_ROOT | Root required |
| 3 | EXIT_UNSUPPORTED_BOARD | Board not supported |
| 4 | EXIT_DTB_NOT_FOUND | DTB file not found |
| 5 | EXIT_DTC_FAILED | dtc compilation/decompilation failed |
| 6 | EXIT_VERIFY_FAILED | Post-write verification failed |
| 7 | EXIT_BACKUP_FAILED | Backup creation failed |
| 8 | EXIT_RESTORE_FAILED | Restore from backup failed |
| 9 | EXIT_NO_BACKUP | No backup found for restore |
| 10 | EXIT_INTERNAL_ERROR | Unexpected internal error |
