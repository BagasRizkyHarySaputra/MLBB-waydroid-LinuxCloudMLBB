# mlbb-waydroid

Run **Mobile Legends: Bang Bang (MLBB)** on Linux via Waydroid — and optionally stream it to your Android phone so the laptop does the heavy lifting and the phone stays cool.

>  **BAN RISK — READ THIS FIRST**
>
> MLBB's anti-cheat (Moonton) is not rejected by this setup today, and the game is
> playable in real matches. **However, server-side detection can happen at any time.**
> Running a mobile game inside an emulation/translation layer is a pattern anti-cheat
> vendors actively look for. **Use a secondary account. Do not use your main account.**
> You accept this risk entirely on your own.

---

## Table of contents

- [What this is](#what-this-is)
- [Architecture](#architecture)
- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Usage — the `mlbb` command](#usage--the-mlbb-command)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Streaming to your phone](#streaming-to-your-phone)
- [Performance tuning](#performance-tuning)
- [FAQ](#faq)
- [Documentation](#documentation)
- [Credits](#credits)
- [License](#license)

---

## What this is

A collection of scripts and configs that turn a Linux desktop into an MLBB machine:

1. **Local play** — Waydroid (Android 13 / LineageOS 20 in an LXC container) runs the
   arm64 build of MLBB using Intel's `libhoudini` ARM translation layer.
2. **Cloud-gaming mode** — [Sunshine](https://github.com/LizardByte/Sunshine) encodes the
   screen and your phone runs [Artemis](https://github.com/ClassicOldSong/moonlight-android)
   (a Moonlight fork) to display it. The phone only decodes video — it never renders the
   game, so it stays cool and battery-friendly.

It was developed and tested on **Kali GNU/Linux Rolling + Hyprland (Wayland)** with an
Intel i5-13420H (Intel UHD iGPU) + NVIDIA RTX 2050, but the Waydroid gameplay part is
distro-agnostic. The Wayland-specific fixes (multi-touch, `wlr` capture) are documented
so X11 users know what does and does not apply.

---

## Architecture

```
┌─────────────────────────── LAPTOP ───────────────────────────┐
│                                                              │
│   ┌─────────────────────────────────────────────┐            │
│   │  Waydroid (Android 13, LXC container)        │            │
│   │    └── MLBB (arm64 via libhoudini)           │            │
│   │          └── rendered by Intel iGPU          │            │
│   └───────────────────────┬─────────────────────┘            │
│                           │ Wayland surface                  │
│                           ▼                                  │
│   ┌─────────────────────────────────────────────┐            │
│   │  Sunshine                                    │            │
│   │    capture = wlr   (Hyprland/Wayland)        │            │
│   │    encode  = vaapi (Intel iGPU, QuickSync)   │            │
│   └───────────────────────┬─────────────────────┘            │
│                           │ H.264/HEVC over LAN (5 GHz WiFi)  │
└───────────────────────────┼──────────────────────────────────┘
                            ▼
┌─────────────────────── PHONE ────────────────────────────────┐
│   Artemis (Moonlight fork)                                    │
│     multi-touch screen input  ──►  sent back to Sunshine      │
│     video decode only (no game rendering)                     │
└──────────────────────────────────────────────────────────────┘
```

---

## Features

- **One-command launcher** (`mlbb`) that brings up Waydroid, the Android UI, MLBB,
  and Sunshine together — and tears them down cleanly.
- **Working multi-touch** — the joystick no longer releases when you tap a skill.
  This is the single most important fix in this repo; see
  [docs/CONTROLS.md](docs/CONTROLS.md).
- **Persistent NAT** — Android gets internet automatically when the container starts,
  handled by a udev rule (not a fragile systemd `.path` unit).
- **Thermal / performance profiles** (`cpu-profile`, `gpu-tune.sh`) to keep an
  Intel laptop from throttling at 90 °C while gaming.
- **Sunshine auto-config** for Intel VAAPI encoding — no NVIDIA driver upgrade required.
- **Latency tooling** (`mlbb latency`) for WiFi power-save, jitter and bitrate advice.
- **Reset script** (`wd-reset.sh`) that untangles every known Waydroid stuck state.

---

## Requirements

**Required**

| Component | Notes |
|---|---|
| Linux with `binder` support | Kernel module `binder_linux` (most distros ship it) |
| [Waydroid](https://waydroid.com/) | `apt install waydroid lxc` |
| `adb` (Android platform-tools) | For installing/controlling apps |
| `iptables` | For the container NAT |
| Python 3 | Waydroid's own tooling |

**For the streaming part**

| Component | Notes |
|---|---|
| [Sunshine](https://github.com/LizardByte/Sunshine) | Host encoder. `.deb`, Flatpak or AppImage |
| [Artemis](https://github.com/ClassicOldSong/moonlight-android) | Client. **Required for multi-touch** |
| Intel GPU with VAAPI encode | Strongly recommended (QuickSync). See [FAQ](#faq) |
| 5 GHz WiFi or Ethernet | 2.4 GHz works but with much higher latency/jitter |

**Compositor**

| Compositor | Status |
|---|---|
| Hyprland / wlroots (Wayland) |  Fully supported (`capture = wlr`) |
| Other Wayland compositors |  Should work with wlr screencopy; multi-touch fix is Hyprland-specific |
| X11 |  Use `capture = x11`. The Hyprland multi-touch bug does not apply, but the fix won't either |

---

## Quick start

```bash
git clone https://github.com/<you>/mlbb-waydroid.git
cd mlbb-waydroid

# Install scripts, systemd units, udev rules and the Waydroid overlay
sudo ./install.sh

# (first time only) set up Waydroid + MLBB — see docs/WAYDROID-SETUP.md
mlbb
```

Day-to-day:

```bash
mlbb            # bring everything up and launch MLBB
mlbb status     # check what's running
mlbb down       # shut it all down
mlbb help       # full command reference
```

> **Waydroid itself must be initialised first** (Android image + GApps + libhoudini +
> MLBB installed). `install.sh` only installs *this project*; it does not bootstrap
> Waydroid. Follow [docs/WAYDROID-SETUP.md](docs/WAYDROID-SETUP.md).

---

## Usage — the `mlbb` command

```
mlbb <command> [option]        (no argument = "up")
```

| Command | What it does |
|---|---|
| `up`, `start` | Start Waydroid container + session, open the Android UI (fullscreen on workspace 4), set immersive fullscreen, disable Google Assistant, launch MLBB, and start Sunshine if it isn't running. |
| `down`, `stop` | Stop MLBB + UI + session + container. Add `--all` to also stop Sunshine. |
| `restart` | `down` then `up`. **Heavy** — a weak laptop can freeze here. Prefer `up`. |
| `status`, `st` | Show the state of every component: session, container, UI, MLBB, Sunshine, NAT, multi-touch fix, window. |
| `ui` | Open the Android UI only (no game launch). |
| `net` | Print everything you need to connect Artemis from the phone (IP, SSID, Sunshine state, pairing steps). `net addr` prints just the IP. |
| `latency on` | Turn WiFi power-save off, apply CPU + iGPU performance tuning. |
| `latency off` | Restore WiFi power-save. |
| `latency status` | Show WiFi band/rate/ping and give bitrate advice for the current band. |
| `help`, `-h`, `--help` | Show help. |

### Companion scripts (installed to `/usr/local/bin`)

| Script | Purpose |
|---|---|
| `mlbb` | Main launcher (above). |
| `wd-reset.sh` | **Run with `sudo`.** Full Waydroid reset when it gets stuck. |
| `wd-ui.sh` | Open the Waydroid UI (used by `mlbb`). |
| `waydroid-nat.sh` | Idempotent NAT setup (called by udev). |
| `cpu-profile` | `quiet` / `balanced` / `performance` / `status` Intel-pstate profiles. |
| `gpu-tune.sh` | Raise Intel iGPU min/boost frequency while gaming. |
| `mlgame.sh` | "Game mode": kill resource-hogging wallpapers, tune CPU/iGPU. |
| `livewallpaper.sh` | Start/stop the video wallpaper (decoded on NVIDIA via NVDEC). |
| `ml-stream.sh` | Hook Sunshine calls for the "Mobile Legends" entry. |
| `ml-headless.sh` | Optional virtual-monitor helper (kept for reference; unused in the default 1-display setup). |

---

## How it works

### Waydroid + libhoudini
Waydroid runs a full Android 13 system in an LXC container. MLBB ships arm64 native
libraries, so Intel's [`libhoudini`](https://github.com/casualsnek/waydroid_script)
translation layer is installed to execute them on x86_64. GApps (MindTheGapps) are
installed so Google login works.

### Display sizing
Android's render resolution comes from `persist.waydroid.width` / `persist.waydroid.height`
in `/var/lib/waydroid/waydroid.cfg` **read at container start**. If these are set,
Waydroid marks the display as non-maximized and the window is created at exactly that
size. The Hyprland window must match **1:1** or mouse/touch coordinates drift.

### Multi-touch — the core fix
Hyprland emits a `wl_pointer.motion` event on every touch-down (via `refocus()` →
`mouseMoveUnified()` → `sendPointerMotion()`). Android's `InputDispatcher` then refuses
the touch stream:

```
Dropping move event because a pointer for a different device is already active in display 0
```

The fix is to **disable the `wayland_pointer` device inside Android** with a tiny IDC
file in Waydroid's overlay. Full explanation in [docs/CONTROLS.md](docs/CONTROLS.md).

### NAT
The container subnet (`192.168.240.0/24`) is masqueraded so Android has internet.
Because the `waydroid0` interface only appears *after* the session starts, a
`systemd .path` unit does not reliably fire — a **udev rule** does:

```
ACTION=="add", SUBSYSTEM=="net", KERNEL=="waydroid0", TAG+="systemd", ENV{SYSTEMD_WANTS}="waydroid-nat.service"
```

### Streaming
Sunshine captures the Wayland output (`capture = wlr`) and encodes it with **Intel VAAPI**
(`encoder = vaapi`, `LIBVA_DRIVER_NAME=iHD`). The phone runs Artemis and sends touches back
as real multi-touch events.

---

## Troubleshooting

The most common problems and their fixes. A full reference lives in
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

| Symptom | Cause | Fix |
|---|---|---|
| **"Container service is already running"** but status is STOPPED | A leftover `dnsmasq` still holds `192.168.240.1`, so `waydroid-net.sh start` fails silently. The message is a lie. | `pkill -9 -f "dhcp-range 192.168.240"` and `pkill -9 -f waydroid-net`, then restart |
| Container stuck **FROZEN** | Waydroid `suspend_action = freeze` | `sudo lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid` (or set `suspend_action = stop`) |
| Same "already running" error, but with stuck cgroups | Empty leftover cgroups | `sudo rmdir /sys/fs/cgroup/lxc.monitor.waydroid /sys/fs/cgroup/lxc.payload.waydroid`, then `systemctl reset-failed waydroid-container` |
| **Click/touch coordinates are off**, or the game is stretched with black bars | Window size ≠ Android resolution, or you used `adb shell wm size` | Set the size via `persist.waydroid.width/height` and restart the container. Never use `wm size`. |
| **Joystick releases when tapping a skill** | Hyprland sends `wl_pointer.motion` on touch | Install `overlay/wayland_pointer.idc` (the multi-touch fix) |
| **A Hyprland rule silently stops working** | An invalid rule name earlier in the file aborts parsing of the rest | Check `hyprctl configerrors`; use `suppressevent maximize fullscreen`, not `nofullscreenrequest` |
| **Window appears on every workspace and can't be moved** | You used the `pin` rule | Remove `pin` from your window rules |
| **Laptop overheats / stutters** | Extra virtual monitors, CPU-decoding video wallpapers, or heavy background apps | See [Performance tuning](#performance-tuning) |
| **Nothing fixed it** | — | `sudo wd-reset.sh` and try again |

---

## Streaming to your phone

Full guide: [docs/STREAMING.md](docs/STREAMING.md). The short version:

1. **Install Sunshine** on the laptop. On Debian/Kali the official `.deb` needs
   `libminiupnpc18`, which newer distros don't ship (they ship `libminiupnpc21`).
   See [docs/STREAMING.md](docs/STREAMING.md#installing-sunshine-on-kali--debian-trixie)
   for the dummy-package + symlink workaround.
2. **Configure Sunshine**:
   ```ini
   capture = wlr
   encoder = vaapi
   adapter_name = /dev/dri/renderD128
   native_pen_touch = enabled
   output_name = eDP-1        # your monitor name
   ```
   and run Sunshine with `LIBVA_DRIVER_NAME=iHD` (see [FAQ](#faq)).
3. **Open the web UI** at `https://<laptop-ip>:47990` (accept the self-signed cert).
4. **Install Artemis** on the phone (`com.limelight.noir`) — stock Moonlight is
   single-touch only and cannot play a MOBA.
5. **Pair**: Artemis → *Add host manually* → laptop IP → enter the PIN shown by Sunshine.
6. **Play**: choose the "Mobile Legends" entry.

Ports to allow: `47984-47990/tcp`, `48010/tcp`, `47998-48000/udp`.

---

## Performance tuning

### The `latency` command
```bash
mlbb latency on       # WiFi power_save off + CPU/iGPU tuning
mlbb latency status   # band, rate, ping + bitrate advice
mlbb latency off      # restore defaults
```

### Biggest wins
1. **WiFi power-save off** — single largest latency factor.
   `iw dev wlan0 set power_save off` + `nmcli connection modify <conn> wifi.powersave 2`
2. **Use 5 GHz** — measured here: 143 → 960 Mbit/s, gateway ping 5–94 ms → 2–3.5 ms.
3. **Match client bitrate to the band**:
   - 2.4 GHz → 8–15 Mbps, 720p, H.264
   - 5 GHz → 20–30 Mbps, 1080p, H.264 or HEVC
   > Raising bitrate on 2.4 GHz makes latency *worse*, not better — the buffer just
   > gets longer.
4. **Kill resource hogs**: video wallpapers that decode on the CPU (should use NVDEC),
   extra virtual monitors, and heavy background apps.

### CPU / thermal
```bash
cpu-profile balanced      # boot default — prevents 90 °C throttling
cpu-profile performance   # maximum clocks while playing
cpu-profile quiet         # lowest heat (turbo off, 60% max)
gpu-tune.sh on            # lock Intel iGPU to high clocks
mlgame.sh on              # kill wallpapers + tune
```

### Sunshine low-latency encoder settings
```ini
vaapi_quality = speed
vaapi_rc = cbr
qp = 28
fec_percentage = 20
intra_refresh = 25
min_threads = 4
```

---

## FAQ

**Can I use the NVIDIA GPU for Waydroid / MLBB?**
No. Waydroid needs a GPU userspace driver built against Android's **bionic libc**. NVIDIA
does not ship one. Waydroid therefore uses the Intel iGPU (or your integrated GPU). The
NVIDIA GPU can still be used for other things (e.g. video decoding with NVDEC), and on
hybrid laptops it often already is.

**Why not use NVENC for Sunshine?**
The Sunshine binary bundles a CUDA runtime that requires a newer driver than 550
(`cudaErrorInsufficientDriver`). Rather than risk a driver upgrade that could break a
hybrid-graphics desktop, this project uses **Intel VAAPI** instead — which is also
lighter on the system. If your NVIDIA driver is new enough, `encoder = nvenc` may work
for you.

**`vainfo` shows an NVIDIA driver and encoding fails.**
`vainfo` is picking NVIDIA's NVDEC driver, which only exposes `VAEntrypointVLD` (decode),
not `VAEntrypointEncSlice` (encode). Force the Intel driver:
```bash
LIBVA_DRIVER_NAME=iHD vainfo
```
and make sure Sunshine runs with `LIBVA_DRIVER_NAME=iHD` too. This is why the systemd
unit sets that environment variable.

**Does this work on X11?**
The gameplay part does, with `capture = x11`. The Hyprland multi-touch fix and the
`wlr` capture path are Wayland-specific. The multi-touch bug is a Hyprland issue, so on
X11 you may not need the IDC overlay at all.

**Will I get banned?**
The risk is real and the author accepts it by using a secondary account. Anti-cheat
detection can be server-side and delayed. **Do not use your main account.**

**Why does the phone stay cool?**
The phone only decodes a video stream; all game rendering happens on the laptop.

---

## Documentation

| File | Contents |
|---|---|
| [docs/WAYDROID-SETUP.md](docs/WAYDROID-SETUP.md) | Full Waydroid bootstrap: init, libhoudini, GApps, ADB, MLBB install |
| [docs/CONTROLS.md](docs/CONTROLS.md) | Input, the multi-touch fix, immersive mode, focus-stealing apps |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptom → cause → fix reference, reset procedure |
| [docs/STREAMING.md](docs/STREAMING.md) | Sunshine + Artemis setup, encoder choice, latency work |
| [docs/id/](docs/id/) | Original Indonesian notes (`SETUP.id.md`, `STREAMING-KE-HP.id.md`) |

---

## Credits

This project stands on the work of others:

- **[Waydroid](https://waydroid.com/)** — the Android-in-a-container runtime.
- **[casualsnek/waydroid_script](https://github.com/casualsnek/waydroid_script)** — libhoudini & GApps installer.
- **[LizardByte/Sunshine](https://github.com/LizardByte/Sunshine)** — the streaming host.
- **[ClassicOldSong/moonlight-android (Artemis)](https://github.com/ClassicOldSong/moonlight-android)** — the client that makes multi-touch work.
- **[Moonlight](https://moonlight-stream.org/)** — the streaming protocol/client lineage.
- **Hyprland PR [#4071](https://github.com/hyprwm/Hyprland/pull/4071)** — which identified the touch + pointer event interaction that causes the multi-touch breakage.

---

## License

[MIT](LICENSE) — do whatever you want, no warranty. See the [ban-risk disclaimer](#mlbb-waydroid) again before you use your main account.
