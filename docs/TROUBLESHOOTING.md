# Troubleshooting

Symptom → cause → fix. When in doubt, run the reset script first:

```bash
sudo wd-reset.sh          # full Waydroid reset (see below)
mlbb up
```

---

## Quick reference

| Symptom | Jump to |
|---|---|
| "Container service is already running" but it's stopped | [dnsmasq zombie](#1-container-service-is-already-running-but-status-is-stopped) |
| Container shows FROZEN | [Frozen container](#2-container-frozen) |
| Same "already running" error, cgroups stuck | [Stuck cgroups](#3-stuck-cgroups) |
| `lxc.mount.entry = tmpfs dev` fails | [Rootfs /dev mount failure](#4-rootfs-dev-mount-failure) |
| Black bars, stretched content, misaligned clicks | [Resolution](#5-resolution-black-bars-and-stretched-content) |
| `fullscreen` rule does nothing | [Fullscreen rule](#6-fullscreen-rule-does-nothing) |
| A window rule suddenly stops working | [Invalid rule name](#7-a-window-rule-stops-working--invalid-rule-name) |
| Window appears on every workspace | [pin rule](#8-window-appears-on-every-workspace) |
| Joystick releases when tapping a skill | [Multi-touch](CONTROLS.md#multi-touch--the-core-fix) |
| Laptop overheats / stutters | [Lag and heat](#9-lag-and-overheating) |
| Android has no internet | [NAT](#10-no-internet-inside-android) |
| Nothing else works | [Reset script](#11-the-reset-script-wd-resetsh) |

---

## 1. "Container service is already running" but status is STOPPED

This message is misleading — it almost never means that. It means Waydroid's container
process is holding a stale DBus name, and the real failure is happening *below* it.

### Root cause

A leftover **`dnsmasq`** process from a previous session is still bound to the container
gateway address `192.168.240.1`. When Waydroid tries to start networking it runs
`waydroid-net.sh start`, which fails with *"Address already in use"*. That failure aborts
the session, so LXC never spawns, so no process owns the container — yet the stale DBus
name remains, producing the "already running" lie.

The real error is visible if you start the session by hand:

```
RuntimeError: Command failed: % /usr/lib/waydroid/data/scripts/waydroid-net.sh start
```

### Fix

```bash
sudo pkill -9 -f 'dhcp-range 192.168.240'
sudo pkill -9 -f waydroid-net

# then bring it back up
mlbb up
```

Related LXC error you may see alongside it:

```
Failed to attach veth to bridge "waydroid0", bridge interface doesn't exist
```

That is a *consequence* — the bridge was torn down by the same restart. Running the
network script (or the reset script) recreates it:

```bash
sudo /usr/lib/waydroid/data/scripts/waydroid-net.sh start
```

---

## 2. Container FROZEN

Waydroid freezes the container when the session suspends. If it comes back frozen:

```bash
sudo lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid
```

To avoid this, use `stop` instead of `freeze` as the suspend action. In
`/var/lib/waydroid/waydroid.cfg`:

```ini
[waydroid]
suspend_action = stop
```

This makes the container genuinely restart rather than trying to resume a frozen one.

Check the state:

```bash
sudo lxc-info -P /var/lib/waydroid/lxc -n waydroid -sH     # RUNNING / FROZEN / STOPPED
waydroid status
```

---

## 3. Stuck cgroups

Symptom: the "already running" error again, `waydroid status` says STOPPED, and no
Waydroid process exists. Inspect the cgroups:

```bash
ls -d /sys/fs/cgroup/lxc*.waydroid*
```

If `lxc.monitor.waydroid` and/or `lxc.payload.waydroid` exist with an empty
`cgroup.procs`, they are orphaned:

```bash
sudo rmdir /sys/fs/cgroup/lxc.monitor.waydroid
sudo rmdir /sys/fs/cgroup/lxc.payload.waydroid

sudo pkill -9 -f 'waydroid container'
sudo pkill -9 -f lxc-start
sudo systemctl reset-failed waydroid-container
sudo systemctl start waydroid-container
```

---

## 4. Rootfs `/dev` mount failure

```
lxc-start: waydroid: run_buffer: Script exited with status 126
lxc-start: waydroid: lxc_end: Failed to run lxc.hook.post-stop for container "waydroid"
```

The `lxc.mount.entry = tmpfs dev` line cannot mount because the container rootfs is not
mounted at the expected path. Mount the images manually so the rootfs exists:

```bash
sudo mount -o loop,ro /var/lib/waydroid/images/system.img  /usr/lib/x86_64-linux-gnu/lxc/rootfs
sudo mount -o loop,ro /var/lib/waydroid/images/vendor.img  /usr/lib/x86_64-linux-gnu/lxc/rootfs/vendor
```

Then stop/start the container. The reset script handles this cleanup automatically.

---

## 5. Resolution, black bars and stretched content

### Symptoms

- Content stretched horizontally (not letterboxed), with black bars.
- Clicks/touches land in the wrong place.
- Game content shifted to one side.

### Cause

Android renders at one resolution while the window is a different size. Waydroid's HWC
does **not** re-render Android when the window changes size — it stretches the existing
surface. Also, if you used `adb shell wm size`, you created an *override* layered on top
of the real display, which compounds the problem.

### Fix

Set the resolution properly, in **both** files, then restart the container:

`/var/lib/waydroid/waydroid.cfg`

```ini
[properties]
persist.waydroid.width = 1920
persist.waydroid.height = 1080
```

`/var/lib/waydroid/waydroid_base.prop`

```
persist.waydroid.width=1920
persist.waydroid.height=1080
```

```bash
sudo wd-reset.sh
```

Set these to **your monitor resolution** and make the window fullscreen — then 1:1 and
fullscreen coincide and there are no bars.

### Why container restart is mandatory

In `wayland-hwc.cpp`, `choose_width_height()` reads `persist.waydroid.width/height` and
also sets `display->isMaximized = false` when they are present. This happens **before
Android boots**, so:

- `waydroid prop set persist.waydroid.width ...` at runtime → no effect.
- Editing the files requires a container restart.

### Verify (don't trust your eyes)

```bash
# Android's real size
adb shell wm size          # "Physical size: 1920x1080"  (no "Override size" line!)
```

Pixel-check the window edges for black bars (a small script beats a screenshot, which is
easy to misjudge):

```bash
hyprctl clients -j | jq -r '.[] | select(.class=="Waydroid") | "\(.at) \(.size)"'
grim /tmp/s.png
# crop the window rect and average each edge; uniform dark edges = black bar
```

---

## 6. `fullscreen` rule does nothing

Two causes:

1. **`float` and `fullscreen` conflict.** A floating window will not go fullscreen by
   rule. Turn floating off first:
   ```bash
   hyprctl dispatch togglefloating address:<addr>
   hyprctl dispatch fullscreen 0 address:<addr>
   ```
2. **`hyprctl dispatch fullscreen` needs the window focused.** Focus it first:
   ```bash
   hyprctl dispatch focuswindow address:<addr>
   hyprctl dispatch fullscreen 0 address:<addr>
   ```

`mlbb up` performs focus → fullscreen in the correct order.

---

## 7. A window rule stops working — invalid rule name

**Hyprland aborts parsing the rest of the config when it hits an invalid rule.** So one
bad line silently disables every rule after it.

A real example: `nofullscreenrequest` is **not a valid rule name** in Hyprland 0.52.2.
It produced a config error and caused a subsequent `size 1600 900` rule to be ignored —
the window ended up tiled at `1908x1037`.

**Always check after editing:**

```bash
hyprctl configerrors
```

Correct names:

```conf
windowrulev2 = suppressevent maximize fullscreen, class:^(Waydroid)$
windowrulev2 = float, class:^(Waydroid)$
windowrulev2 = size 1920 1080, class:^(Waydroid)$
windowrulev2 = center, class:^(Waydroid)$
windowrulev2 = workspace 4 silent, class:^(Waydroid)$
windowrulev2 = fullscreen, class:^(Waydroid)$
```

---

## 8. Window appears on every workspace

You used the `pin` rule. Pinned windows exist on all workspaces and cannot be moved —
great for a HUD, terrible for a game you want to move away from.

Remove `pin` from your window rules and reload:

```bash
hyprctl reload
```

If it is already pinned, unpin it once:

```bash
hyprctl dispatch pin address:<addr>     # toggles off
```

---

## 9. Lag and overheating

### Known heavy hitters

| Cause | Symptom | Fix |
|---|---|---|
| **Extra virtual monitor** (e.g. a `HEADLESS-*` output) | CPU spikes, ~92 °C, fan maxed | Delete it: `hyprctl output remove HEADLESS-2`, and remove any `monitors.conf` entry |
| **Video wallpaper decoding on CPU** | One process at ~180 % CPU | Run it with hardware decode, e.g. mpvpaper with `hwdec=nvdec`; or stop it while playing |
| **Heavy background apps** | Constant load | An AI coding agent/IDE can sit at 90 %+ alone. Close them while playing |
| **2.4 GHz WiFi** | High jitter | Use 5 GHz; see [STREAMING.md](STREAMING.md#latency) |

### Diagnose

```bash
# who is eating CPU
ps -eo pcpu,pmem,comm --sort=-pcpu | head

# temperature
sensors | grep -E 'Package id 0|x86_pkg'

# CPU / iGPU controls
cpu-profile status
gpu-tune.sh status
```

### Mitigate

```bash
cpu-profile balanced       # boot default; keeps it below ~85 °C
cpu-profile performance    # more FPS, more heat — use briefly
cpu-profile quiet          # coolest
gpu-tune.sh on             # lock iGPU high clocks (less stutter, not more heat)
mlgame.sh on               # kill wallpapers + tune
```

> `mlbb restart` is much heavier than `mlbb up`. On a thermally limited laptop, prefer
> `up`.

---

## 10. No internet inside Android

Confirm the NAT rules exist:

```bash
sudo iptables -t nat -S POSTROUTING | grep 192.168.240
sudo iptables -S FORWARD | grep waydroid0
sudo sysctl net.ipv4.ip_forward
```

If missing, apply them (idempotent):

```bash
sudo waydroid-nat.sh
```

### Why the udev rule (and not systemd `.path`)

`waydroid0` only exists **after** the session starts, so a `systemd .path` unit that
watches for the interface does not fire reliably. A **udev rule** does:

`/etc/udev/rules.d/70-waydroid-nat.rules`

```
ACTION=="add", SUBSYSTEM=="net", KERNEL=="waydroid0", TAG+="systemd", ENV{SYSTEMD_WANTS}="waydroid-nat.service"
```

```bash
sudo udevadm control --reload-rules
```

Verify with:

```bash
journalctl -u waydroid-nat.service -n5 --no-pager     # "NAT waydroid OK"
```

---

## 11. The reset script (`wd-reset.sh`)

When the container is wedged, this script resets everything. **Run it with `sudo`** —
without root, its `su` call fails with `Authentication failure` and the status degrades to
*"Insufficient privileges"*.

```bash
sudo wd-reset.sh              # reset + start a fresh session
sudo wd-reset.sh --no-start   # reset only, don't start
```

What it does, in order:

1. Kill the UI (`show-full-ui`) and stop the session.
2. Stop `waydroid-container.service` and kill the container processes.
3. **Kill the `dnsmasq` zombie** (`dhcp-range 192.168.240`) and force `waydroid-net.sh stop`.
4. Unmount the container rootfs and any loop devices (`losetup -D`).
5. Remove stale runtime state: `/run/waydroid-lxc/*`,
   `/run/lxc/lock/var/lib/waydroid`.
6. Remove orphaned cgroups (`lxc.monitor.waydroid`, `lxc.payload.waydroid`).
7. Kill whatever is holding the container DBus name.
8. `systemctl reset-failed waydroid-container`.
9. Start a fresh session as the desktop user:
   ```bash
   su <user> -c 'XDG_RUNTIME_DIR=/run/user/<uid> WAYLAND_DISPLAY=wayland-1 nohup waydroid session start'
   ```
10. `lxc-unfreeze` in case it came back frozen.

Success looks like:

```
[...] Android with user 0 is ready
```

and `lxc-info ... -sH` reports `RUNNING`.

---

## Diagnostics cheat sheet

```bash
waydroid status                                   # session + container
sudo lxc-info -P /var/lib/waydroid/lxc -n waydroid -sH
systemctl status waydroid-container --no-pager
journalctl -u waydroid-container -n30 --no-pager
tail -n50 /var/lib/waydroid/waydroid.log
mlbb status                                       # all of the above + ML/UI/Sunshine/NAT
```
