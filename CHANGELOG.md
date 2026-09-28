# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versions follow [SemVer](https://semver.org/).

## [1.0.0] — 2026-09-28

First public release.

### Added
- `mlbb` — one-command launcher handling Waydroid container/session, Android UI,
  immersive fullscreen, Google Assistant suppression, MLBB launch and Sunshine.
  Subcommands: `up`, `down [--all]`, `restart`, `status`, `ui`, `net`, `latency`,
  `help`.
- **Multi-touch fix** — `overlay/wayland_pointer.idc` disables the `wayland_pointer`
  device inside Android, resolving the Hyprland `wl_pointer.motion` conflict
  (Hyprland PR #4071). Holding the joystick and tapping a skill now works.
- `wd-reset.sh` — full Waydroid reset covering zombie dnsmasq, stuck cgroups,
  unmounted rootfs and orphaned DBus names.
- `waydroid-nat.sh` + udev rule — persistent NAT applied automatically when
  `waydroid0` appears (systemd `.path` does not fire reliably).
- `cpu-profile` — Intel pstate profiles (`quiet` / `balanced` / `performance`).
- `gpu-tune.sh` — raises Intel iGPU min/boost frequency while gaming.
- `mlgame.sh` — game mode: stops resource-hogging wallpapers, tunes CPU/iGPU.
- `livewallpaper.sh` — video wallpaper using NVIDIA NVDEC decode.
- Sunshine config tuned for Intel VAAPI low-latency streaming.
- `install.sh` — installs scripts, systemd units, udev rules and the Waydroid overlay.
- Documentation: `docs/WAYDROID-SETUP.md`, `docs/CONTROLS.md`,
  `docs/TROUBLESHOOTING.md`, `docs/STREAMING.md`.

### Notes
- NVIDIA GPUs cannot be used for Waydroid (no bionic-libc userspace driver).
- NVENC is not usable with driver 550; Intel VAAPI is used instead.
- Anti-cheat ban risk exists — use a secondary account.

[1.0.0]: https://github.com/BagasRizkyHarySaputra/MLBB-waydroid-LinuxCloudMLBB/releases/tag/v1.0.0
