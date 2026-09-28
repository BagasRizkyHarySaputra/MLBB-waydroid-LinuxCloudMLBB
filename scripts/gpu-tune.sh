#!/usr/bin/env bash
# ============================================================
#  gpu-tune.sh - tune Intel iGPU + kurangi beban desktop
#  Pakai: gpu-tune.sh {status|on|off}
# ============================================================
set -u
CARD=${CARD:-/sys/class/drm/card0}
BOOST=$CARD/gt_boost_freq_mhz
MINF=$CARD/gt_min_freq_mhz
STATE=/run/gpu-tune.state

status(){
  echo "== Intel iGPU =="
  printf "  cur   = %s MHz\n" "$(cat $CARD/gt_cur_freq_mhz 2>/dev/null)"
  printf "  boost = %s MHz\n" "$(cat $BOOST 2>/dev/null)"
  printf "  min   = %s MHz\n" "$(cat $MINF 2>/dev/null)"
  echo "== pengguna GPU (desktop) =="
  ps -eo pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -6 | sed 's/^/  /'
}

case "${1:-status}" in
  on)
    # naikin min freq supaya GPU nggak down-clock saat gaming
    echo 900  > "$MINF" 2>/dev/null || true
    echo 1400 > "$BOOST" 2>/dev/null || true
    echo on > "$STATE" 2>/dev/null || true
    echo "[gpu-tune] ON  -> min=900MHz boost=1400MHz"
    ;;
  off)
    echo 100 > "$MINF" 2>/dev/null || true
    echo off > "$STATE" 2>/dev/null || true
    echo "[gpu-tune] OFF -> min=100MHz (hemat daya)"
    ;;
  status|*) status ;;
esac
