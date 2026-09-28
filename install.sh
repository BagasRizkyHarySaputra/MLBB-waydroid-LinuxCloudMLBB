#!/usr/bin/env bash
# ============================================================
#  install.sh - pasang mlbb-waydroid ke sistem
#  Jalankan: sudo ./install.sh
# ============================================================
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "jalankan dengan sudo: sudo ./install.sh"; exit 1; }

# user tujuan (pemilik sesi grafis) — bisa dioverride: sudo TARGET_USER=foo ./install.sh
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || { echo "user '$TARGET_USER' tidak ada"; exit 1; }
TARGET_UID="$(id -u "$TARGET_USER")"
HERE="$(cd "$(dirname "$0")" && pwd)"

ok(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

echo "== mlbb-waydroid installer =="
echo "   user  : $TARGET_USER ($TARGET_UID)"
echo "   home  : $TARGET_HOME"
echo "   src   : $HERE"
echo

# ---------- 1. dependencies ----------
echo "== [1/6] cek dependencies =="
PKGS_MISSING=""
for p in waydroid lxc adb python3 iptables; do
  command -v "$p" >/dev/null 2>&1 || PKGS_MISSING="$PKGS_MISSING $p"
done
[ -n "$PKGS_MISSING" ] && warn "perlu diinstal:$PKGS_MISSING (opsional: sunshine)" || ok "dependency dasar lengkap"

# ---------- 2. install scripts ----------
echo "== [2/6] install scripts ke /usr/local/bin =="
for f in "$HERE"/scripts/*; do
  b="$(basename "$f")"
  install -m 755 -o root -g root "$f" "/usr/local/bin/$b"
  ok "$b"
done

# ---------- 3. systemd units ----------
echo "== [3/6] install systemd units =="
for f in "$HERE"/config/*.service; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  install -m 644 "$f" "/etc/systemd/system/$b"
  ok "$b"
done
# drop-in NAT untuk waydroid-container
mkdir -p /etc/systemd/system/waydroid-container.service.d
install -m 644 "$HERE/config/waydroid-container-nat.conf" \
  /etc/systemd/system/waydroid-container.service.d/10-nat.conf
ok "waydroid-container.service.d/10-nat.conf"

# ---------- 4. udev rules ----------
echo "== [4/6] install udev rules =="
for f in "$HERE"/config/*.rules; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  install -m 644 "$f" "/etc/udev/rules.d/$b"
  ok "$b"
done
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

# ---------- 5. sunshine + portal config (milik user) ----------
echo "== [5/6] install config user (sunshine, portal) =="
mkdir -p "$TARGET_HOME/.config/sunshine" \
         "$TARGET_HOME/.config/systemd/user" \
         "$TARGET_HOME/.config/xdg-desktop-portal"
cp -n "$HERE/config/sunshine.conf"  "$TARGET_HOME/.config/sunshine/sunshine.conf"  2>/dev/null || true
cp -n "$HERE/config/apps.json"      "$TARGET_HOME/.config/sunshine/apps.json"      2>/dev/null || true
cp -n "$HERE/config/sunshine.service" "$TARGET_HOME/.config/systemd/user/sunshine.service" 2>/dev/null || true
cp -n "$HERE/config/hyprland-portals.conf" \
      "$TARGET_HOME/.config/xdg-desktop-portal/hyprland-portals.conf" 2>/dev/null || true
chown -R "$TARGET_USER:" "$TARGET_HOME/.config/sunshine" \
      "$TARGET_HOME/.config/systemd/user/sunshine.service" \
      "$TARGET_HOME/.config/xdg-desktop-portal/hyprland-portals.conf" 2>/dev/null || true
ok "config sunshine + portal"

# ---------- 6. waydroid overlay (multi-touch fix) ----------
echo "== [6/6] pasang overlay multi-touch fix =="
OVL="/var/lib/waydroid/overlay/system/usr/idc"
if [ -d /var/lib/waydroid ]; then
  mkdir -p "$OVL"
  install -m 644 "$HERE/overlay/wayland_pointer.idc" "$OVL/wayland_pointer.idc"
  ok "wayland_pointer.idc (multi-touch fix)"
else
  warn "Waydroid belum terinstall -> lewati overlay (jalankan ulang installer setelah install waydroid)"
fi

systemctl daemon-reload 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user daemon-reload 2>/dev/null || true

cat <<EOF

== SELESAI ==
Langkah berikutnya:
  1. Pastikan Waydroid sudah diinisialisasi (waydroid init + GApps + libhoudini)
  2. Pasang MLBB di dalam Waydroid
  3. Aktifkan binder_linux:
       echo binder_linux | sudo tee /etc/modules-load.d/waydroid.conf
       echo 'options binder_linux devices=binder,hwbinder,vndbinder' | sudo tee /etc/modprobe.d/waydroid.conf
  4. Jalankan:   mlbb
  5. Streaming ke HP: install Sunshine + Artemis (lihat README)

Cek status:  mlbb status
Bantuan   :  mlbb help
EOF
