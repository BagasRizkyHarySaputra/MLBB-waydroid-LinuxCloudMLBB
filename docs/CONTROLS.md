# Controls, Input & Multi-Touch

Everything about making input work: clicks landing where you point, and — most
importantly — **multi-touch**, so you can hold the joystick and tap a skill at the same
time.

---

## The rules that must never be broken

1. **The Wayland window must be exactly the same pixel size as the Android display.**
   Any mismatch stretches the content and makes every touch coordinate wrong.
2. **`persist.waydroid.fake_touch` must be OFF when streaming real touch.**
   That property collapses all input into a single mouse pointer — useful when you only
   have a mouse, fatal when Artemis is sending real multi-touch.
3. **Never `adb shell wm size`.** It is an override layered on top of the real display.
   Size Android via `persist.waydroid.width/height` instead (see
   [WAYDROID-SETUP.md](WAYDROID-SETUP.md#9-display-resolution-and-window-size)).

---

## Mouse → tap (no streaming)

Running with only a mouse, Android expects touch events. Convert clicks to taps:

```bash
waydroid prop set persist.waydroid.fake_touch '*'
# restart the session for it to take effect
```

**Turn this OFF** as soon as you stream from a phone:

```bash
waydroid prop set persist.waydroid.fake_touch ''
```

---

## Multi-touch — the core fix

### Symptom

In any MOBA: hold the movement joystick with one finger, tap a skill with a second
finger → **the joystick releases**. Only roughly two simultaneous touches ever work.

### Root cause

Hyprland emits a **pointer motion event on every touch-down**:

```
onTouchDown() → refocus(TOUCH_COORDS) → mouseMoveUnified() → sendPointerMotion()
```

So Android receives a `wl_pointer.motion` event *interleaved* with the touch stream.
Android's `InputDispatcher` then rejects the touches:

```
Dropping move event because a pointer for a different device is already active in display 0
```

That message, repeated dozens of times, is the smoking gun. You can watch it live:

```bash
adb logcat | grep -i 'Dropping move event'
```

**Confirmed upstream:** Hyprland PR [#4071](https://github.com/hyprwm/Hyprland/pull/4071)
(merged 2023-12-06) — *"touch events and cursor move events come together and makes
waydroid not handling touch events correctly."*

> **Updating Hyprland does not fix this.** The relevant code
> (`refocus()` / `mouseMoveUnified()`) is identical in v0.52.2, v0.56.2 and `main`.
> `follow_mouse = 0` does not help either.
>
> Patching Waydroid's `touch_handle_cancel` is also useless: Hyprland never sends a
> `wl_touch` cancel event (`wl_touch cancel = 0`).

### The fix — disable `wayland_pointer` inside Android

Waydroid's `libinputreader.so` registers several virtual devices from pipes under
`/dev/input/`:

| Pipe | Android device |
|---|---|
| `/dev/input/wl_touch_events` | `wayland_touch` |
| `/dev/input/wl_pointer_events` | `wayland_pointer` |
| `/dev/input/wl_keyboard_events` | `wayland_keyboard` |
| `/dev/input/wl_tablet_events` | `wayland_tablet` |

Each of these honours the Android **IDC** property `device.disabled`. So the conflict
can be removed at the Android side, **without patching any binary**, by disabling only
the pointer device:

**File:** `/var/lib/waydroid/overlay/system/usr/idc/wayland_pointer.idc`

```
device.disabled = 1
```

#### Why the overlay path

Waydroid's rootfs (`system.img`) is read-only. Writing to
`/var/lib/waydroid/rootfs/system/usr/idc/` would not survive. The overlay directory
`/var/lib/waydroid/overlay/system/` is merged over the system image at boot, so files
placed there are **persistent**.

This repo ships the file at [`overlay/wayland_pointer.idc`](../overlay/wayland_pointer.idc);
`install.sh` copies it into place.

#### Verify the fix

```bash
adb shell dumpsys input | grep -c wayland_pointer     # expect: 0
adb logcat | grep -c 'Dropping move event'            # expect: 0 while playing
```

Also confirm `wayland_touch` is still present — that is the device that carries your
fingers.

### Undo

```bash
sudo rm /var/lib/waydroid/overlay/system/usr/idc/wayland_pointer.idc
sudo wd-reset.sh
```

---

## Supporting settings

These are not the fix itself, but they prevent related interference.

### Sunshine must expose a touchscreen

In `~/.config/sunshine/sunshine.conf`:

```ini
native_pen_touch = enabled
```

Without this, Sunshine does not create its `libvirtualhid Touchscreen` device and there
is nothing for Android to receive.

### Ignore Sunshine's stray pen tablet

Sunshine also creates a `libvirtualhid Pen Tablet`, which registers as a *second*
touchscreen and reintroduces the "different device" conflict. Ignore it with udev:

**File:** `/etc/udev/rules.d/71-sunshine-notablet.rules`

```
ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="libvirtualhid Pen Tablet", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

Reload:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Afterwards `hyprctl devices` should no longer list a tablet.

### Disable 3/4-finger compositor gestures

A three-finger tap can be swallowed as a workspace gesture instead of reaching the game.
Comment these out in your Hyprland config (this repo's reference config does):

```conf
# gesture = 3, horizontal, workspace
# gesture = 4, up/down, ...zoom......
# gesture = 3, up, ...OverviewToggle...
```

> `gestures:workspace_swipe_touch = 0` already disables touch swipes; the gestures above
> concern the mouse/touchpad path, but disabling them removes ambiguity.

---

## Disabling Google Assistant

On Waydroid with GApps, Google Assistant frequently grabs focus mid-game. Disable it:

```bash
adb shell settings put secure assistant "null"
adb shell settings put secure voice_interaction_service "null"
adb shell settings delete secure assistant_service
adb shell settings put secure assist_gesture_enabled 0
adb shell settings put secure assistant_gesture_enabled 0
adb shell settings put secure assist_touch_and_hold_enabled 0
adb shell pm disable-user --user 0 com.google.android.googlequicksearchbox
adb shell am force-stop com.google.android.googlequicksearchbox
```

The package is `com.google.android.googlequicksearchbox` (GSA / "Velvet").

---

## Other Android display settings

| Goal | Command |
|---|---|
| Fullscreen (hide bars) | `adb shell settings put global policy_control "immersive.full=*"` |
| Hide touch developer overlay | `adb shell settings put system pointer_location 0` |
| Tablet-ish scaling | `adb shell wm density 240` |

---

## Diagnostic toolkit

When input misbehaves, work down the stack:

| Layer | Tool | What to look for |
|---|---|---|
| Kernel evdev | `evtest /dev/input/event<N>` | `ABS_MT_SLOT`, `ABS_MT_TRACKING_ID` for each finger. Sunshine's touchscreen has `ABS_MT_SLOT Max=15`. |
| Wayland protocol | `wev` | `wl_touch.down/motion/up` with distinct `id`s, and whether `wl_pointer.motion` is interleaved. |
| Android input | `adb shell dumpsys input` | Registers devices; each has `Sources`, `Classes` (`TOUCH_MT`), and the mapper mode. |
| Android dispatch | `adb logcat \| grep -i 'Dropping\|InputDispatcher'` | The "different device" rejection message. |

Install the two host tools:

```bash
sudo apt install evtest wev
```

### Finding the right event device

```bash
grep -A2 'Name="libvirtualhid' /proc/bus/input/devices
```

Typical mapping after Sunshine starts:

| event | Device |
|---|---|
| `event19` | `libvirtualhid Keyboard` |
| `event20` | `libvirtualhid Mouse` |
| `event21` | `libvirtualhid Mouse (Absolute)` |
| `event22` | `libvirtualhid Touchscreen` ← this is the one |
| `event23` | `libvirtualhid Pen Tablet` |

> In Waydroid the Android input devices are **pipes**, not evdev nodes — you cannot read
> them with `getevent` *inside* Android. Use `wev` on the host instead.

### Confirming Android supports multi-touch

```bash
adb shell dumpsys input | sed -n '/wayland_touch/,/^$/p'
```

Expect `Sources: TOUCHSCREEN`, `Classes: TOUCH_MT`, and a mapper in `DIRECT` mode with a
wide `TrackingId` range. That is Android saying "yes, many fingers".
