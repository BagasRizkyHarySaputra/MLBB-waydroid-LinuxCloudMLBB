#!/usr/bin/env bash
# Buka UI Waydroid di sesi Wayland/Hyprland user saat ini.
# XDG_RUNTIME_DIR & WAYLAND_DISPLAY dideteksi otomatis (bisa dioverride).
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export GDK_BACKEND=wayland
unset DISPLAY
exec waydroid show-full-ui
