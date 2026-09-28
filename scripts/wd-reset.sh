#!/usr/bin/env bash
# ============================================================
#  wd-reset.sh - reset TOTAL Waydroid sampai benar-benar bersih
#  Akar masalah yg ditangani:
#   - dnsmasq zombie pegang 192.168.240.1  -> session gagal start
#   - bridge waydroid0 nyangkut
#   - mount rootfs sisa
#   - cgroup/lock/dbus nyangkut
#   - container FROZEN (suspend_action)
#  Pakai: sudo wd-reset.sh [--no-start]
# ============================================================
set -u
USER_UID=${SUDO_UID:-1000}
RT="/run/user/$USER_UID"
WD="wayland-1"

echo "[wd-reset] 1. stop UI + session"
pkill -9 -f "show-full-ui" 2>/dev/null
pkill -9 -f "waydroid session" 2>/dev/null
sleep 1

echo "[wd-reset] 2. stop service + kill container"
systemctl stop waydroid-container 2>/dev/null
sleep 2
pkill -9 -f "waydroid container" 2>/dev/null
pkill -9 -f "lxc-start.*waydroid" 2>/dev/null
sleep 1

echo "[wd-reset] 3. KILL dnsmasq zombie (AKAR MASALAH)"
pkill -9 -f "dhcp-range 192.168.240" 2>/dev/null
pkill -9 -f "waydroid-net" 2>/dev/null
sleep 2
rem=$(pgrep -cf "dhcp-range 192.168.240" 2>/dev/null || echo 0)
echo "           sisa dnsmasq waydroid: $rem"

echo "[wd-reset] 4. stop bridge"
/usr/lib/waydroid/data/scripts/waydroid-net.sh stop force >/dev/null 2>&1
sleep 1

echo "[wd-reset] 5. bersihkan mount + loop"
for m in $(mount | grep -E "waydroid/rootfs|waydroid/lxc" | awk '{print $3}' | sort -r); do
  umount -lf "$m" 2>/dev/null
done
losetup -D 2>/dev/null

echo "[wd-reset] 6. bersihkan lock/cgroup/dbus"
rm -f /run/waydroid-lxc/* 2>/dev/null
rm -rf /run/lxc/lock/var/lib/waydroid 2>/dev/null
rmdir /sys/fs/cgroup/lxc.monitor.waydroid /sys/fs/cgroup/lxc.payload.waydroid 2>/dev/null
DBUSPID=$(busctl --system status id.waydro.Container 2>/dev/null | awk -F= '/^PID=/{print $2}')
[ -n "${DBUSPID:-}" ] && [ "$DBUSPID" != "0" ] && kill -9 "$DBUSPID" 2>/dev/null
systemctl reset-failed waydroid-container 2>/dev/null

echo "[wd-reset] 7. cek tak ada yg pegang 192.168.240.1"
held=$(ss -ulnp 2>/dev/null | grep -c "192.168.240.1")
echo "           held: $held"

[ "${1:-}" = "--no-start" ] && { echo "[wd-reset] selesai (tanpa start)"; exit 0; }

echo "[wd-reset] 8. start session (spawn container)"
su "$(id -nu $USER_UID)" -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=$WD nohup waydroid session start >/tmp/wd-session.log 2>&1 &"
sleep 30
echo "[wd-reset] 9. unfreeze kalau perlu"
lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid 2>/dev/null
sleep 2
echo "[wd-reset] status: $(lxc-info -P /var/lib/waydroid/lxc -n waydroid -sH 2>&1)"
tail -2 /tmp/wd-session.log 2>/dev/null
