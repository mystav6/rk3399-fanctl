# Installation Guide

This guide covers a complete fresh installation of `rk3399-fanctl` on a
NanoPC-T4 (or compatible RK3399 board) running Armbian.

---

## Requirements

| Requirement | Details |
|---|---|
| Board | NanoPC-T4, NanoPi M4, RockPro64, ROCK Pi 4 |
| OS | Armbian 26.x (Debian 12/13 base) |
| Kernel | 6.x current or edge |
| Packages | `git`, `device-tree-compiler` |
| Access | SSH or local terminal with sudo |

---

## Step 1 — Install dependencies

```bash
sudo apt update
sudo apt install -y git device-tree-compiler
```

---

## Step 2 — Clone the repository

```bash
cd ~
git clone git@github.com:mystav6/rk3399-fanctl.git
cd rk3399-fanctl
```

> **Note:** If you prefer HTTPS over SSH:
> ```bash
> git clone https://github.com/mystav6/rk3399-fanctl.git
> ```

---

## Step 3 — Install system files

```bash
# Main binary
sudo cp scripts/rk3399-fanctl /usr/sbin/rk3399-fanctl
sudo cp scripts/rk3399-fanctl /sbin/rk3399-fanctl
sudo chmod 0755 /usr/sbin/rk3399-fanctl /sbin/rk3399-fanctl

# Libraries
sudo mkdir -p /usr/share/rk3399-fanctl
sudo cp scripts/common.sh        /usr/share/rk3399-fanctl/
sudo cp scripts/common.sh        /usr/sbin/
sudo cp scripts/dtb-lib.sh       /usr/share/rk3399-fanctl/
sudo cp scripts/dtb-lib.sh       /usr/sbin/
sudo cp scripts/calibrate-lib.sh /usr/share/rk3399-fanctl/
sudo cp scripts/calibrate-lib.sh /usr/sbin/

# Kernel hook (auto re-applies settings after kernel update)
sudo cp scripts/kernel-hook.sh /etc/kernel/postinst.d/rk3399-fanctl
sudo chmod 0755 /etc/kernel/postinst.d/rk3399-fanctl

# apt hook (safety net for kernel hook)
sudo cp defaults/apt-hook.conf /etc/apt/apt.conf.d/99rk3399-fanctl

# State directory
sudo mkdir -p /var/lib/rk3399-fanctl/backup

# Log file
sudo touch /var/log/rk3399-fanctl.log
```

---

## Step 4 — Configure sudo (passwordless access)

The tool requires root for DTB writes and PWM control.
Add a sudoers rule so commands work without password prompts
(required for SSH-based monitoring integration):

```bash
sudo tee /etc/sudoers.d/rk3399-fanctl << 'SUDOERS'
mysta ALL=(ALL) NOPASSWD: /usr/sbin/rk3399-fanctl
SUDOERS
sudo chmod 0440 /etc/sudoers.d/rk3399-fanctl

# Verify
sudo visudo -c
```

---

## Step 5 — Verify installation

```bash
# Check syntax
sudo sh -n /usr/sbin/rk3399-fanctl && echo "syntax OK"

# Check version
sudo rk3399-fanctl --version

# Show current fan status
sudo rk3399-fanctl --show
```

Expected output:

```
=== rk3399-fanctl status ===

Active DTB:      /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
DTB levels:      0,12,18,255
Saved state:     none
```

---

## Step 6 — First configuration

### Option A — Calibrate first (recommended)

Run the interactive calibration to find the optimal minimum PWM
for your specific fan:

```bash
sudo rk3399-fanctl --calibrate
```

Follow the on-screen instructions. The tool will:
1. Spin the fan to maximum
2. Step down PWM and ask you to confirm at each level
3. Calculate recommended `cooling-levels` with a safety margin
4. Apply them automatically if you confirm

### Option B — Set known values directly

If you already know what values you want:

```bash
# Example: quiet operation, fan starts at PWM 32
sudo rk3399-fanctl --levels 0,32,96,255

# Or just set the minimum PWM (preserves other levels)
sudo rk3399-fanctl --min-pwm 30
```

---

## Step 7 — Verify and monitor

```bash
# Verify DTB matches saved state
sudo rk3399-fanctl --verify

# Check live PWM value
cat /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1

# Show full status
sudo rk3399-fanctl --show
```

---

## Monitoring integration (optional)

If you run the T4 System monitoring stack (Pi5 + Flask API + dashboard),
follow these additional steps.

### 7a — Update status-export.sh

Replace `/opt/monitoring/status-export.sh` with the version from
`integration/t4-1-status-export.sh`:

```bash
sudo cp integration/t4-1-status-export.sh /opt/monitoring/status-export.sh
sudo chmod +x /opt/monitoring/status-export.sh

# Test
sudo /opt/monitoring/status-export.sh
cat /var/lib/monitoring/t4-1-status.json | python3 -m json.tool
```

The JSON should now contain a `"fan"` section:

```json
{
  "hostname": "nanopct4-1",
  "fan": {
    "pwm": 32,
    "pwm_max": 255,
    "pwm_pct": 13,
    "cooling_level": 1,
    "cooling_levels_total": 4,
    "configured_levels": "0,32,96,255",
    "state": "on"
  },
  ...
}
```

### 7b — Add Flask API endpoints (Pi5)

On Pi5, add the fan API endpoints to `/opt/monitoring-api/api.py`.
Insert the contents of `integration/api-fan-endpoints.py` before the
`if __name__ == "__main__":` block, then restart:

```bash
sudo systemctl restart pi5-monitoring-api
curl -s http://127.0.0.1:5000/api/fan/status/t41 | python3 -m json.tool
```

### 7c — Deploy Fan Control dashboard card (Pi5)

```bash
# Create dashboard directory
sudo mkdir -p /var/www/dashboard-fan

# Copy HTML
sudo cp integration/dashboard-fan-card.html /var/www/dashboard-fan/index.html

# Add nginx location (inside server { } block, before closing })
sudo nano /etc/nginx/sites-available/heartbeat
```

Add before the closing `}`:

```nginx
location = /dashboard-fan { return 301 /dashboard-fan/; }
location /dashboard-fan/ {
    root /var/www; index index.html;
    try_files $uri $uri/ /dashboard-fan/index.html;
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Access at: `http://192.168.0.109:9999/dashboard-fan/`

---

## Useful commands reference

```bash
# Show current status
sudo rk3399-fanctl --show

# Set cooling-levels
sudo rk3399-fanctl --levels 0,32,96,255

# Set minimum PWM only
sudo rk3399-fanctl --min-pwm 30

# Interactive calibration
sudo rk3399-fanctl --calibrate

# Restore original DTB
sudo rk3399-fanctl --restore

# Verify DTB matches saved state
sudo rk3399-fanctl --verify

# Re-apply after manual kernel update
sudo rk3399-fanctl --reapply

# Export fan status as JSON
sudo rk3399-fanctl --export-json

# Check live PWM
cat /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1
```

---

## Uninstall

```bash
# Restore original DTB first
sudo rk3399-fanctl --restore

# Remove binaries
sudo rm -f /usr/sbin/rk3399-fanctl /sbin/rk3399-fanctl

# Remove libraries
sudo rm -rf /usr/share/rk3399-fanctl
sudo rm -f /usr/sbin/common.sh /usr/sbin/dtb-lib.sh /usr/sbin/calibrate-lib.sh

# Remove hooks
sudo rm -f /etc/kernel/postinst.d/rk3399-fanctl
sudo rm -f /etc/apt/apt.conf.d/99rk3399-fanctl

# Remove sudoers
sudo rm -f /etc/sudoers.d/rk3399-fanctl

# Remove state (optional - keeps your backup)
sudo rm -rf /var/lib/rk3399-fanctl
sudo rm -f /var/log/rk3399-fanctl.log
```

> **Note:** DTB backup is preserved in `/var/lib/rk3399-fanctl/backup/`
> even after uninstall until you explicitly remove the state directory.

---

## Tested versions

| Version | Board | Armbian | Kernel | Status |
|---|---|---|---|---|
| v0.5.0 | NanoPC-T4 | 26.8.0-trunk | 6.18.37-current-rockchip64 | ✅ Tested |
