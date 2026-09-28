# Streaming MLBB to Your Phone

Turn the laptop into the "console" and the phone into a thin client. The phone only
**decodes video** — it never renders the game — so it stays cool and sips battery.

```
[Laptop]                              [Phone]
 ML in Waydroid                        Artemis (Moonlight fork)
        │                                    ▲
        ▼                                    │
 Sunshine (VAAPI encode) ── WiFi/LAN ──► hardware decoder
        ▲                                    │
        └──────── touch events ◄─────────────┘
```

> **Prerequisite:** the multi-touch fix in [CONTROLS.md](CONTROLS.md) must already be
> applied, otherwise the game is unplayable over the stream.

---

## 1. Install Sunshine

### Flatpak (simplest)

```bash
flatpak install -y flathub dev.lizardbyte.app.Sunshine
```

### AppImage

```bash
mkdir -p ~/Apps && cd ~/Apps
# grab the latest from https://github.com/LizardByte/Sunshine/releases
wget https://github.com/LizardByte/Sunshine/releases/latest/download/Sunshine-<ver>-x86_64.AppImage
chmod +x Sunshine-*.AppImage
```

### Installing Sunshine on Kali / Debian trixie

The official `.deb` is built for a specific Debian/Ubuntu release. Pick the closest:
`sunshine_<ver>-1+debiantrixie_amd64.deb` for Kali / Debian trixie.

```bash
# find the exact filename
curl -sL "https://github.com/LizardByte/Sunshine/releases/expanded_assets/<tag>" \
  | grep -oE 'sunshine_[^"]+debiantrixie_amd64\.deb' | head -1

sudo apt install -y ./sunshine_<ver>-1+debiantrixie_amd64.deb
```

#### If the install fails: `libminiupnpc18` is not installable

Newer distros ship `libminiupnpc21` (2.3.x); Sunshine's control file asks for the older
package name `libminiupnpc18` (2.2.8). The ABI is compatible, so make a dummy meta-package
that satisfies the dependency and a symlink for the soname:

```bash
sudo apt install -y equivs libminiupnpc21 miniupnpc

cat > /tmp/libminiupnpc18.control <<'EOF'
Section: libs
Priority: optional
Standards-Version: 3.9.2
Package: libminiupnpc18
Version: 2.2.8-1
Provides: libminiupnpc18
Depends: libminiupnpc21
Maintainer: local <local@localhost>
Description: Dummy package satisfied by libminiupnpc21
EOF

cd /tmp && equivs-build libminiupnpc18.control
sudo dpkg -i /tmp/libminiupnpc18_2.2.8-1_all.deb

# soname bridge
sudo ln -sf /usr/lib/x86_64-linux-gnu/libminiupnpc.so.21 \
            /usr/lib/x86_64-linux-gnu/libminiupnpc.so.18
sudo ldconfig

sunshine --version     # should print the version, not a loader error
```

---

## 2. Configure Sunshine

Web UI: `https://<laptop-ip>:47990` — accept the self-signed certificate warning.
Set the admin username/password on first run (this is for the web manager, not the
phone).

### `~/.config/sunshine/sunshine.conf`

```ini
# --- capture / encode ---
capture = wlr                       # Hyprland / wlroots. Use "x11" on X11.
encoder = vaapi                     # Intel QuickSync. See "Why not NVENC?" below.
adapter_name = /dev/dri/renderD128  # Intel render node
output_name = eDP-1                 # your monitor (check `hyprctl monitors`)
fps = 60

# --- touch input (REQUIRED for multi-touch) ---
native_pen_touch = enabled

# --- low-latency tuning ---
vaapi_quality = speed
vaapi_rc = cbr
qp = 28
fec_percentage = 20
intra_refresh = 25
min_threads = 4
```

### Critical: `LIBVA_DRIVER_NAME=iHD`

Sunshine must run with `LIBVA_DRIVER_NAME=iHD`, or VAAPI picks the **NVIDIA NVDEC**
driver — which only exposes `VAEntrypointVLD` (decode), not `VAEntrypointEncSlice`
(encode) — and encoding fails with *"No usable encoding entrypoint"*-style errors.

Check:

```bash
LIBVA_DRIVER_NAME=iHD vainfo | grep -E 'driver version|EntrypointEnc'
# expect: Driver version: Intel iHD driver ...   and ... : VAEntrypointEncSlice
```

### Why not NVENC?

Sunshine's bundled CUDA runtime requires a newer driver than 550
(`cudaErrorInsufficientDriver`). Upgrading the driver on a hybrid-graphics laptop risks
breaking the desktop. Intel VAAPI works and leaves the discrete GPU free. If your NVIDIA
driver is new enough, `encoder = nvenc` may work — try it.

> Harmless log noise: `av1_vaapi` errors (no AV1 encoder on that GPU) and
> `Failed to gain/drop CAP_SYS_ADMIN` (not needed for `capture = wlr`).

### systemd user service

`~/.config/systemd/user/sunshine.service`

```ini
[Unit]
Description=Sunshine game streaming host
After=waydroid-container.service
Wants=waydroid-container.service

[Service]
Type=simple
Environment=XDG_RUNTIME_DIR=%t
Environment=WAYLAND_DISPLAY=wayland-1
Environment=LIBVA_DRIVER_NAME=iHD
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/sunshine
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

> **Gotcha:** do **not** use `WantedBy=graphical-session.target` — that target is inactive
> on many Hyprland setups, so the service never starts. `default.target` works.
> `XDG_RUNTIME_DIR=%t` keeps it portable across users.

```bash
systemctl --user daemon-reload
systemctl --user enable --now sunshine.service
```

### Add the "Mobile Legends" app

Web UI → **Applications** → **Add New**:

| Field | Value |
|---|---|
| Name | `Mobile Legends` |
| Command | `/usr/local/bin/ml-stream.sh` |
| Working Dir | *(leave blank)* |

`ml-stream.sh` (shipped in `scripts/`, installed by `install.sh`) starts Waydroid, opens
the UI, launches MLBB, and positions the window so Sunshine captures the game.

---

## 3. Ports

```bash
sudo ufw allow 47984/tcp      # HTTPS
sudo ufw allow 47989/tcp      # HTTP
sudo ufw allow 47990/tcp      # web UI
sudo ufw allow 48010/tcp      # RTSP control
sudo ufw allow 47998:48000/udp  # video / audio
```

If your firewall INPUT policy is already `ACCEPT`, nothing to do — check with
`sudo iptables -S INPUT | head -1`.

---

## 4. Install the client on the phone

**Use Artemis** — it is a Moonlight fork with working multi-touch and touch-friendly
internationalisation:

- `github.com/ClassicOldSong/moonlight-android` (APK in Releases)

Stock **Moonlight** (Play Store) is single-touch only — pressing two fingers does not
register as two touches, which makes a MOBA unplayable. Acceptable for testing only.

---

## 5. Pair

1. Phone and laptop on the **same network** (laptop joined to the phone's hotspot is the
   most reliable: no dependence on the local WiFi).
2. In Artemis choose **Add Host Manually** and enter the laptop IP.
   Get it with `mlbb net` / `mlbb net addr`.
3. Sunshine shows a **4-digit PIN** — enter it on the phone (or enter the phone's PIN in
   the web UI, depending on direction).
4. Select **Mobile Legends**.

### Host discovery (optional)

Sunshine advertises `_nvstream._tcp` via mDNS, so Artemis can auto-discover:

```bash
sudo systemctl enable --now avahi-daemon
```

---

## 6. Client settings that matter

| Setting | 2.4 GHz | 5 GHz |
|---|---|---|
| Resolution | 1280×720 | 1920×1080 |
| FPS | 60 | 60 |
| Video bitrate | **8–15 Mbps** | **20–30 Mbps** |
| Codec | H.264 | H.264 or HEVC |
| "Optimize game settings" | ON | ON |

> **Do not set a high bitrate on 2.4 GHz.** The extra data has nowhere to go, the buffer
> grows, and latency gets *worse*. Lower bitrate = smoother on a weak link.

### Touch mode in Artemis

- Input mode: **Multi-touch** (not Trackpad, not SingleTouch)
- Leave *"3-finger tap for keyboard"* gestures **off** — otherwise three fingers open the
  keyboard instead of reaching the game

---

## Latency

### Measure first

```bash
mlbb latency status
```

Shows WiFi band, negotiated rate, power-save state and gateway ping. The gateway ping is
the number that matters — it is your floor for input latency.

### Apply the optimisations

```bash
mlbb latency on      # power_save off + CPU/iGPU tuning
mlbb latency off     # restore
```

Under the hood:

```bash
iw dev wlan0 set power_save off
nmcli connection modify "<conn>" wifi.powersave 2
cpu-profile balanced
gpu-tune.sh on
```

### Results seen in practice

| | Before | After |
|---|---|---|
| Band | 2.4 GHz (2462 MHz) | 5 GHz (5180 MHz) |
| Link rate | ~143 Mbit/s | ~960 Mbit/s |
| Gateway ping | 5–94 ms (heavy jitter) | 2–3.5 ms (mdev ~1 ms) |

The two changes that mattered most were **disabling WiFi power-save** and **moving to
5 GHz**.

### What does NOT matter

- **WARP / Tailscale / VPNs** — traffic to the phone is on a private LAN range that is in
  the VPN's exclude list, so it goes directly out `wlan0`. Verify:
  ```bash
  ip route get <phone-gateway-ip>     # should say "dev wlan0", not a tun device
  ```

---

## Troubleshooting the stream

| Problem | Fix |
|---|---|
| Phone can't find the host | `systemctl --user status sunshine`; check ports (`ss -tlnp \| grep 4798`); check the firewall; confirm the IP with `mlbb net` |
| Stutter / macroblocking | Lower bitrate; switch HEVC → H.264; confirm 5 GHz |
| High input lag | Disable power-save; move to 5 GHz; reduce bitrate; close other network users |
| Phone still gets hot | It shouldn't. If it does, drop to 720p60 or 1080p30 |
| Black screen / no video | Check `capture` (`wlr` vs `x11`) and that `output_name` matches `hyprctl monitors` |
| Multi-touch still broken | [CONTROLS.md](CONTROLS.md) — the IDC overlay must be present |

---

## Honest expectations

- **Input latency still exists** (~20–40 ms on a good LAN). Ranked play will feel it.
- **Multi-touch requires Artemis**, not stock Moonlight.
- **Ban risk remains** — this is still Waydroid. Use an alt account.
- This setup is best for **casual play**, not competitive climbing.
