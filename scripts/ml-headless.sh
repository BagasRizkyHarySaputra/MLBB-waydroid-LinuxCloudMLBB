#!/usr/bin/env bash
# ============================================================
#  ml-headless.sh - siapkan monitor VIRTUAL (HEADLESS-2) + Waydroid
#  di sana, fullscreen, TANPA ganggu desktop utama (eDP-1).
#  Sunshine capture HEADLESS-2 -> HP cuma lihat ML.
#  Pakai: ml-headless.sh [setup|cleanup|status]
# ============================================================
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
MON=HEADLESS-2
W=1600; H=900
WS=4

log(){ echo "[ml-headless $(date +%H:%M:%S)] $*"; }

setup(){
  # 1. pastikan monitor virtual ada
  if ! hyprctl monitors -j 2>/dev/null | grep -q "\"$MON\""; then
    log "bikin monitor virtual $MON..."
    hyprctl output create headless "$MON" >/dev/null 2>&1
    sleep 2
  fi
  # 2. ukuran & posisi (taruh di kanan, biar gak numpuk)
  hyprctl keyword monitor "$MON,${W}x${H}@60,1920x0,1" >/dev/null 2>&1
  sleep 1
  # 3. workspace khusus di monitor itu
  hyprctl keyword workspace "$WS, monitor:$MON" >/dev/null 2>&1
  log "monitor $MON = ${W}x${H}, workspace $WS"
}

cleanup(){
  log "hapus monitor virtual $MON..."
  ADDR=$(hyprctl clients -j 2>/dev/null | python3 -c \
    "import json,sys
try: print([w['address'] for w in json.load(sys.stdin) if w.get('class')=='Waydroid'][0])
except: pass" 2>/dev/null)
  [ -n "${ADDR:-}" ] && hyprctl dispatch movetoworkspace 2,"address:$ADDR" >/dev/null 2>&1
  hyprctl output remove "$MON" >/dev/null 2>&1
  log "selesai"
}

status(){
  echo "monitor:"
  hyprctl monitors -j 2>/dev/null | python3 -c "import json,sys;[print('  ',m['name'],m['width'],'x',m['height']) for m in json.load(sys.stdin)]"
  echo "waydroid:"
  hyprctl clients -j 2>/dev/null | python3 -c "
import json,sys
for w in json.load(sys.stdin):
    if (w.get('class') or '')=='Waydroid':
        print(f\"  ws={(w.get('workspace') or {}).get('id')} mon={w.get('monitor')} fs={w.get('fullscreen')} size={w.get('size')}\")"
}

case "${1:-setup}" in
  setup|"") setup ;;
  cleanup)  cleanup ;;
  status)   status ;;
  *) echo "pakai: ml-headless.sh [setup|cleanup|status]" ;;
esac
