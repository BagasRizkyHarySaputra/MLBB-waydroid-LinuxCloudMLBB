#!/usr/bin/env bash
# ============================================================
#  livewallpaper.sh - jalankan wallpaper video di NVIDIA (NVDEC)
#  Robust: tunggu NVIDIA siap, hindari konflik swww, retry.
#  Pakai: livewallpaper.sh [start|stop|status]
# ============================================================
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
WALL="$HOME/Pictures/wallpapers/blindfolded-fantasy-girl-moewalls-com.mp4"
LOG=/tmp/livewallpaper.log

# env PRIME offload ke RTX
export __NV_PRIME_RENDER_OFFLOAD=1
export __VK_LAYER_NV_optimus=NVIDIA_only
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export LIBVA_DRIVER_NAME=nvidia
export VDPAU_DRIVER=nvidia

MPV_OPTS="load-scripts=no no-audio loop hwdec=nvdec hwdec-codecs=all profile=fast"

nvidia_ready(){
  nvidia-smi -q >/dev/null 2>&1 && \
  [ -e /dev/dri/renderD129 ] && \
  [ -e /dev/nvidia0 ]
}

start(){
  # 1. hindari konflik: matikan wallpaper setter lain
  for p in mpvpaper swww-daemon hyprpaper swaybg; do
    pkill -x "$p" 2>/dev/null && echo "[livewallpaper] stop $p"
  done
  sleep 1

  # 2. tunggu NVIDIA siap (maks ~30s)
  for i in $(seq 1 30); do
    nvidia_ready && break
    sleep 1
  done
  if ! nvidia_ready; then
    echo "[livewallpaper] NVIDIA belum siap, coba tetap jalan..."
  fi

  # 3. video ada?
  if [ ! -f "$WALL" ]; then
    echo "[livewallpaper] wallpaper tidak ada: $WALL"; exit 1
  fi

  # 4. jalankan (retry kalau gagal dlm 3s)
  for attempt in 1 2 3; do
    setsid mpvpaper -o "$MPV_OPTS" '*' "$WALL" >>"$LOG" 2>&1 &
    sleep 3
    if pgrep -x mpvpaper >/dev/null; then
      echo "[livewallpaper] OK (attempt $attempt) - NVDEC aktif"
      return 0
    fi
    echo "[livewallpaper] attempt $attempt gagal, retry..."
    sleep 2
  done
  echo "[livewallpaper] GAGAL start mpvpaper (lihat $LOG)"
  return 1
}

stop(){
  pkill -x mpvpaper 2>/dev/null && echo "[livewallpaper] stopped" || echo "[livewallpaper] tidak jalan"
}

status(){
  if pgrep -x mpvpaper >/dev/null; then
    local pid=$(pgrep -x mpvpaper | head -1)
    printf "[livewallpaper] RUNNING pid=%s CPU=%s%%\n" "$pid" "$(ps -o pcpu= -p $pid | tr -d ' ')"
    printf "  render node: "; sudo -n ls -l /proc/$pid/fd 2>/dev/null | grep -oE "renderD[0-9]+" | sort -u | tr '\n' ' '; echo
    printf "  nvdec lib  : "; sudo -n grep -o "libnvcuvid[^ ]*" /proc/$pid/maps 2>/dev/null | head -1 || echo "?"
  else
    echo "[livewallpaper] tidak jalan"
  fi
}

case "${1:-start}" in
  start|"") start ;;
  stop)     stop ;;
  status)   status ;;
  *) echo "pakai: livewallpaper.sh [start|stop|status]" ;;
esac
