#!/usr/bin/env bash
# ============================================================
#  ml-stream.sh - dipanggil Sunshine saat HP minta "Mobile Legends"
#  Tugas: pastikan Waydroid + ML jalan, window pas, lalu biarkan
#  Sunshine nangkap layarnya.
# ============================================================
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
PKG=com.mobile.legends
ACT=$PKG/com.moba.unityplugin.MobaGameMainActivityWithExtractor
W=1600; H=900; WS=2

log(){ echo "[ml-stream $(date +%H:%M:%S)] $*" >>/tmp/ml-stream.log; }

# 1. NAT + session
sudo -n /usr/local/bin/waydroid-nat.sh >/dev/null 2>&1 || true
if ! waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; then
  log "start session"
  nohup waydroid session start >/dev/null 2>&1 &
  sleep 18
fi

# 2. UI
if ! pgrep -f show-full-ui >/dev/null; then
  log "buka UI"
  setsid waydroid show-full-ui </dev/null >/dev/null 2>&1 &
  sleep 15
fi

# 3. adb + ML
adb connect 192.168.240.112:5555 >/dev/null 2>&1
adb shell am start -n "$ACT" >/dev/null 2>&1
log "ML dibuka"

# 4. window pas di workspace target
for i in 1 2 3 4 5; do
  ADDR=$(hyprctl clients -j 2>/dev/null | /usr/bin/python3 -c \
    "import json,sys
try: print([w['address'] for w in json.load(sys.stdin) if w.get('class')=='Waydroid'][0])
except: pass" 2>/dev/null)
  [ -n "$ADDR" ] && break
  sleep 3
done
if [ -n "${ADDR:-}" ]; then
  hyprctl dispatch setfloating "address:$ADDR" >/dev/null 2>&1
  hyprctl dispatch resizewindowpixel exact $W $H,"address:$ADDR" >/dev/null 2>&1
  hyprctl dispatch movetoworkspace $WS,"address:$ADDR" >/dev/null 2>&1
  hyprctl dispatch workspace $WS >/dev/null 2>&1
  log "window $W x $H @ ws $WS"
fi

# 5. tunggu ML benar2 tampil sebelum Sunshine ambil alih
sleep 45
log "siap di-stream"
