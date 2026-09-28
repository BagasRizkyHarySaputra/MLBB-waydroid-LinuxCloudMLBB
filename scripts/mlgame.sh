#!/usr/bin/env bash
# ============================================================
#  mlgame.sh - mode GAME: matikan perampok resource + tune
#  Pakai: mlgame.sh on|off|status
# ============================================================
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)

HOGS="mpvpaper swaybg hyprpaper"
killed=""

case "${1:-on}" in
  on)
    # 1. matikan wallpaper video (perampok CPU terbesar)
    for p in $HOGS; do
      if pgrep -x "$p" >/dev/null 2>&1; then
        pkill -x "$p" 2>/dev/null && killed="$killed $p"
      fi
    done
    [ -n "$killed" ] && echo "[mlgame] dimatikan:$killed" || echo "[mlgame] tidak ada wallpaper-hog"

    # 2. tune Intel iGPU (min freq naik)
    sudo -n /usr/local/bin/gpu-tune.sh on 2>/dev/null \
      || echo "[mlgame] (jalankan 'sudo gpu-tune.sh on' manual kalau gak ada sudo-n)"

    # 3. CPU: mode balanced (cegah overheat tapi tetap kuat)
    sudo -n /usr/local/bin/cpu-profile balanced 2>/dev/null || true

    echo "[mlgame] mode GAME ON"
    ;;

  off)
    echo "[mlgame] mode GAME OFF (wallpaper tidak dinyalakan otomatis)"
    echo "  untuk balikin wallpaper: jalankan hyprpaper/mpvpaper lagi manual"
    sudo -n /usr/local/bin/gpu-tune.sh off 2>/dev/null || true
    ;;

  status|*)
    echo "== procs =="
    for p in $HOGS; do printf "  %-12s: %s\n" "$p" "$(pgrep -x $p >/dev/null && echo RUN || echo off)"; done
    echo "== gpu =="; /usr/local/bin/gpu-tune.sh status 2>/dev/null | head -5
    ;;
esac
