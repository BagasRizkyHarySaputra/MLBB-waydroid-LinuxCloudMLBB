# Waydroid Setup for Gaming

Complete bootstrap of Waydroid so it can run arm64 games (MLBB) with Google services.

> This guide assumes a Debian-based distro (tested on Kali GNU/Linux Rolling).
> Package names may differ slightly elsewhere.

---

## 1. Prerequisites

| Requirement | Check |
|---|---|
| `binder` kernel support | `modinfo binder_linux` |
| Waydroid | `apt install waydroid lxc` |
| Android platform-tools | `adb version` |
| Python 3 | `python3 --version` |
| ~10 GB free disk | the Android image + GApps + game |

Modern kernels use `memfd` instead of `ashmem`, so the old `ashmem` module is **not**
needed. `binder_linux` **is** required.

---

## 2. Install Waydroid

```bash
sudo apt update
sudo apt install -y waydroid lxc
```

### 2.1 Fix the Python shebang bug (important)

`/usr/bin/waydroid` starts with `#!/usr/bin/env python3`. If you have a conda/pyenv
Python earlier in `PATH`, that interpreter gets used instead — and it does not have the
`dbus` module:

```
ModuleNotFoundError: No module named 'dbus'
```

**Fix A** — point the shebang at the system Python:

```bash
sudo sed -i '1s|.*|#!/usr/bin/python3|' /usr/bin/waydroid
```

**Fix B** — the Debian package does not set `PYTHONPATH`, so the `tools` package is not
importable. Add the path explicitly near the top of `/usr/bin/waydroid` (before
`import tools`):

```python
import sys
sys.path.insert(0, '/usr/lib/waydroid')
```

Both edits together make `waydroid` work regardless of your shell's `PATH`.

### 2.2 Load the binder module

```bash
sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
ls /dev/binder /dev/hwbinder /dev/vndbinder
```

Make it permanent:

```bash
echo binder_linux | sudo tee /etc/modules-load.d/waydroid.conf
echo 'options binder_linux devices=binder,hwbinder,vndbinder' | sudo tee /etc/modprobe.d/waydroid.conf
```

---

## 3. Initialise Android

```bash
waydroid init            # downloads the Android 13 / LineageOS 20 image
sudo systemctl enable --now waydroid-container
waydroid session start
```

If the container gets stuck, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## 4. Add ARM translation + GApps (waydroid_script)

MLBB ships **arm64** native libraries. On x86_64 hardware you need a translation layer.
On **Intel** CPUs use `libhoudini` (not `libndk`, which targets AMD).

```bash
cd /tmp
git clone https://github.com/casualsnek/waydroid_script
cd waydroid_script
python3 -m venv venv
./venv/bin/pip install -r requirements.txt   # tqdm, requests, InquirerPy

# ARM translation (Intel -> libhoudini)
sudo ./venv/bin/python main.py -a 13 install libhoudini

# Google services (MindTheGapps for Android 13)
sudo ./venv/bin/python main.py -a 13 install gapps
```

> Run the script as root (or with `sudo`) — it writes into `/var/lib/waydroid`.

### Verify

```bash
# libhoudini present
ls /var/lib/waydroid/rootfs/system/lib64/libhoudini.so
ls /var/lib/waydroid/rootfs/system/bin/houdini64

# GApps present
ls /var/lib/waydroid/rootfs/system/product/priv-app/Phonesky
```

The native bridge properties should now be active:

```
ro.dalvik.vm.native.bridge=libhoudini.so
ro.dalvik.vm.isa.arm=x86
ro.dalvik.vm.isa.arm64=x86_64
```

`ro.product.cpu.abilist` should include `arm64-v8a`.

---

## 5. Enable ADB access

By default Waydroid's ADB requires authorisation. For headless control, disable that:

Edit `/var/lib/waydroid/waydroid_base.prop`:

```
ro.adb.secure=0
ro.adb.tcp.port=5555
```

Restart the container, then:

```bash
adb connect 192.168.240.112:5555
adb devices        # should show the device as "device"
```

---

## 6. Give Android internet (NAT)

The container has **no internet** until you masquerade its subnet.

```bash
sudo sysctl -w net.ipv4.ip_forward=1

sudo iptables -t nat -A POSTROUTING -s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE
sudo iptables -I FORWARD -i waydroid0 -j ACCEPT
sudo iptables -I FORWARD -o waydroid0 -j ACCEPT
```

Verify inside Android:

```bash
adb shell ping -c2 1.1.1.1        # 0% loss
adb shell curl -s -o /dev/null -w '%{http_code}\n' https://example.com   # 204
```

> This repo automates the rule above with `waydroid-nat.sh` + a **udev rule** that fires
> when `waydroid0` appears. A `systemd .path` unit does *not* work reliably here, because
> the interface only exists after the session starts. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
>
> Note: firewalls that persist across reboots (ufw/firewalld) will wipe these rules —
> re-apply, or use the udev approach.

---

## 7. Install MLBB

MLBB is distributed as an **XAPK** (split APK). Download it from a mirror such as APKPure.
The site requires a browser User-Agent, e.g.:

```bash
curl -A 'Mozilla/5.0 (X11; Linux x86_64)' -L -o mlbb.xapk \
  'https://d.apkpure.com/b/XAPK/com.mobile.legends?version=latest'
```

Unzip and install the arm64 splits together:

```bash
unzip -o mlbb.xapk -d mlbb/
cd mlbb
adb install-multiple \
  com.mobile.legends.apk \
  config.arm64_v8a.apk \
  PlayAssetPack.apk \
  PlayAssetPack.config.countries_fr.apk
```

You should see `Success`.

### Launch activity

```
com.mobile.legends/com.moba.unityplugin.MobaGameMainActivityWithExtractor
```

```bash
adb shell am start -n com.mobile.legends/com.moba.unityplugin.MobaGameMainActivityWithExtractor
```

### Expected result

The anti-cheat (`[zorro] mLibrariesLoaded:true`) initialises, you reach
character creation and hero select, and can play real matches
(verified in-game traffic: ~64–79 ms ping, client 2.2.16.1232.1).

---

## 8. Annoyances to silence

### Google Setup Wizard covering the screen

The wizard can re-appear and block the game. Disable it:

```bash
adb shell pm disable-user --user 0 com.google.android.setupwizard
adb shell settings put global device_provisioned 1
adb shell settings put secure user_setup_complete 1
```

### Status bar / navigation bar

Use immersive mode to hide them (a MOBA wants the whole screen):

```bash
adb shell settings put global policy_control "immersive.full=*"
```

### Google Assistant stealing focus

See [CONTROLS.md](CONTROLS.md#disabling-google-assistant).

---

## 9. Display resolution and window size

Android's render resolution comes from `persist.waydroid.width` / `persist.waydroid.height`
in `/var/lib/waydroid/waydroid.cfg` under `[properties]` (also put it in
`waydroid_base.prop`). **The container must be restarted** for changes to take effect —
the compositor reads these values before Android boots, so `waydroid prop set` at runtime
has no effect.

**Do not use `adb shell wm size`.** That is an *override* on top of the real display and
produces offset content and large black bars when it does not match the window.

**The Wayland window must be exactly the same size as the Android resolution** (1:1),
otherwise pointer/touch coordinates are wrong.

Rule of thumb: set Android to your monitor's resolution (e.g. 1920×1080) and fullscreen
the window; then 1:1 and fullscreen coincide. Details in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#resolution-black-bars-and-stretched-content).

---

## 10. Next steps

- Input, multi-touch and focus fixes: [CONTROLS.md](CONTROLS.md)
- Streaming to a phone: [STREAMING.md](STREAMING.md)
- When things break: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
