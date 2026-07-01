#!/bin/sh
# /etc/kernel/postinst.d/rk3399-fanctl
# Runs automatically after a new kernel is installed.
# Re-applies saved cooling-levels to the new DTB.
#
# Arguments from kernel hook system:
#   $1 = kernel version (e.g. "6.18.37-current-rockchip64")
#   $2 = path to new vmlinuz (unused)

KERNEL_VERSION="$1"
TOOL="/usr/sbin/rk3399-fanctl"
STATE_FILE="/var/lib/rk3399-fanctl/state"

# If tool is not installed or state does not exist, do nothing
[ -x "$TOOL" ]       || exit 0
[ -f "$STATE_FILE" ] || exit 0

# Load saved cooling-levels
saved_levels=$(awk -F= '/^levels=/{print $2}' "$STATE_FILE")
[ -n "$saved_levels" ] || exit 0

echo "rk3399-fanctl: Kernel update detected ($KERNEL_VERSION)"
echo "rk3399-fanctl: Re-applying cooling-levels: $saved_levels"

# Short pause - /boot/dtb symlink may still be redirecting after this hook
sleep 1

if "$TOOL" --levels "$saved_levels" --no-state-update 2>&1; then
    echo "rk3399-fanctl: cooling-levels successfully applied to new DTB"
else
    echo "rk3399-fanctl: WARNING - automatic re-application failed" >&2
    echo "rk3399-fanctl: Run manually: sudo rk3399-fanctl --levels $saved_levels" >&2
    # Do not return error - we don't want to block kernel installation
fi

exit 0
