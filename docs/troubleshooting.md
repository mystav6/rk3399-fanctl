# Troubleshooting

This document captures real issues encountered during development and testing
of `rk3399-fanctl` on NanoPC-T4 with Armbian 26.8.x. It may save hours of
searching for other RK3399 users.

---

## Board stuck at U-Boot screen after adding `fdtoverlays`

### Symptom

After adding the `fdtoverlays` directive to `/boot/extlinux/extlinux.conf`,
the board freezes at the U-Boot screen and does not boot into the OS.

### Cause

Older U-Boot versions on RK3399 (typically flashed to SPI/eMMC on boards
like NanoPC-T4) **do not support the `fdtoverlays` directive in `extlinux.conf`**,
even though newer U-Boot versions do.

Armbian historically handled overlays via `armbianEnv.txt` + `boot.scr` +
`rockchip-fixup.scr` — but newer images (Armbian 26.x) boot purely via
`extlinux.conf` without these helper files, so the overlay mechanism is
not available at all.

This is why `rk3399-fanctl` uses direct DTB modification instead of overlays.

### Recovery

If you encounter this situation:

**1. Prepare an SD card with Armbian** and boot from it.

**2. Identify the eMMC:**
```bash
lsblk
# eMMC is typically mmcblk2, SD card is mmcblk1
```

**3. Mount the boot partition from eMMC:**
```bash
sudo mkdir -p /mnt/emmc
sudo mount -o rw /dev/mmcblk2p1 /mnt/emmc
# Verify you can see the /boot directory:
sudo ls /mnt/emmc/boot/
```

> **Note:** On some images the boot partition may appear empty at first glance —
> try `sudo ls /mnt/emmc/boot/` anyway. The `boot` directory is often nested
> as `/mnt/emmc/boot/`.

**4. Remove the `fdtoverlays` line:**
```bash
sudo sed -i '/fdtoverlays/d' /mnt/emmc/boot/extlinux/extlinux.conf
# Verify the result:
sudo cat /mnt/emmc/boot/extlinux/extlinux.conf
```

**5. Unmount and reboot without SD card:**
```bash
sudo umount /mnt/emmc
sudo reboot
```

---

## `--show` does not display `DTB levels` without root

### Symptom

```
=== rk3399-fanctl status ===
Active DTB:      /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
DTB levels:      (sudo required to read DTB)
Saved state:     0,32,96,255 (applied: ...)
```

### Cause

The DTB file in `/boot/dtb/rockchip/` may have permissions `640` or `600` —
readable only by root. A regular user cannot read it, `dtc` fails and
`--show` displays the informative message.

### Solution

```bash
# Display with root privileges
sudo rk3399-fanctl --show

# Or make the DTB world-readable (optional):
sudo chmod 644 /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
```

> **Note:** `rk3399-fanctl` preserves the original file permissions when
> writing the DTB. If your DTB had `600` before the first `--levels` run,
> fix it manually with `chmod 644` as shown above.

---

## Where are backups and how to restore

### State directory structure

```
/var/lib/rk3399-fanctl/
├── state                          ← current config (cooling-levels, timestamp, kernel)
└── backup/
    ├── rk3399-nanopc-t4.dtb.orig      ← original DTB before first modification
    └── rk3399-nanopc-t4.dtb.orig.meta ← backup metadata (sha256, timestamp)
```

### Restore via tool

```bash
sudo rk3399-fanctl --restore
```

Restores the original DTB and clears the saved state. After reboot the fan
will be controlled by the default `cooling-levels` from the DTB.

### Manual restore (if tool is unavailable)

```bash
sudo cp /var/lib/rk3399-fanctl/backup/rk3399-nanopc-t4.dtb.orig \
        /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
sudo reboot
```

### Verify backup integrity

```bash
# Show backup metadata
cat /var/lib/rk3399-fanctl/backup/rk3399-nanopc-t4.dtb.orig.meta

# Verify backup checksum
sha256sum /var/lib/rk3399-fanctl/backup/rk3399-nanopc-t4.dtb.orig
# Compare with the sha256= value in the .meta file
```

---

## What happens after a kernel update

### Symptom

After `sudo apt upgrade` which installed a new kernel, the fan behaves
as before `rk3399-fanctl` was applied (too loud or not starting at low PWM).

### Cause

When Armbian updates the kernel it:
1. Creates a new directory `/boot/dtb-<new-version>/`
2. Redirects the `/boot/dtb` symlink to the new directory
3. Our modification on the old DTB is lost — the new DTB has default `cooling-levels`

### Automatic protection

`rk3399-fanctl` installs a hook at `/etc/kernel/postinst.d/rk3399-fanctl`
that runs automatically after a new kernel is installed and re-applies saved
`cooling-levels` to the new DTB.

Verify the hook is installed:
```bash
ls -la /etc/kernel/postinst.d/rk3399-fanctl
```

### Manual re-application

If automatic re-application fails or the hook is not installed:
```bash
sudo rk3399-fanctl --reapply
```

---

## Verify fan operation at runtime

Current PWM value of the fan (without reboot):

```bash
cat /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1
```

The value corresponds to the active `cooling-level` — depends on current CPU
temperature and thermal governor settings (`step_wise` in Armbian).

Manual PWM override for testing (temporary, does not survive reboot):

```bash
echo 128 | sudo tee /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1
```

---

## Supported boards and tested hardware

| Board       | Armbian version  | Kernel               | Status    |
|-------------|------------------|----------------------|-----------|
| NanoPC-T4   | 26.8.0-trunk     | 6.18.37-current-rockchip64 | ✅ Tested |
| NanoPi M4   | —                | —                    | 🔲 Untested |
| RockPro64   | —                | —                    | 🔲 Untested |
| ROCK Pi 4   | —                | —                    | 🔲 Untested |

---

## Reporting bugs

If you encounter an issue not described here, please include the output of:

```bash
sudo rk3399-fanctl --show
uname -r
cat /etc/armbian-release | grep -E "VERSION|BOARD|BRANCH"
sudo cat /boot/extlinux/extlinux.conf
```
