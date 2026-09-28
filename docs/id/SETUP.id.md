# MLBB di Waydroid — Ringkasan Setup

## Perintah utama
    ~/ml-waydroid.sh              # main ML (auto semua)
    ~/ml-waydroid.sh stop         # matiin

    /usr/local/bin/livewallpaper.sh {start|stop|status}   # wallpaper NVDEC
    cpu-profile {quiet|balanced|performance|status}        # profil CPU
    sudo gpu-tune.sh {on|off|status}                       # freq Intel iGPU
    mlgame.sh {on|off|status}                              # mode game

## Komponen otomatis
- thermald (service)                -> thermal protection
- cpu-profile.service               -> balanced saat boot (cegah 90C)
- /etc/udev/rules.d/70-waydroid-nat.rules -> NAT otomatis saat waydroid0 muncul
- waydroid-nat.service              -> pasang NAT (idempotent)
- waydroid-container (drop-in 10-nat.conf) -> ExecStartPost NAT
- ~/.config/hypr/hyprland.conf:44   -> autostart livewallpaper NVDEC
- windowrulev2 Waydroid             -> float 950x1036 (input akurat)

## FAKTA PENTING
- Waydroid TIDAK BISA pakai NVIDIA (driver NVIDIA gak ada utk bionic libc/Android).
  GPU untuk Waydroid = Intel iGPU (renderD128). Sudah final, jangan diutak-atik.
- mpvpaper HARUS pakai hwdec=nvdec, kalau tidak -> decode 4K60 di CPU = 180% CPU.
- swww-daemon bentrok dgn mpvpaper -> sudah dimatikan.
- ML harus dibuka via activity: com.moba.unityplugin.MobaGameMainActivityWithExtractor
- Input: persist.waydroid.fake_touch=* (mouse -> tap), window WAJIB 1:1 dgn wm size (950x1036)
- Google Assistant: sudah di-disable (com.google.android.googlequicksearchbox)

## RISIKO
- Anti-cheat Moonton BELUM nolak, tapi ban bisa server-side/blakangan.
- Pakai second account saja.

## PENTING
- Ganti password sudo (pernah bocor di chat).

## UPDATE: mode layar (2026-09-25)
- Android di-set 1600x900 landscape (tablet) + density 240 + immersive fullscreen
- Window Hyprland: floating 1600x900, TANPA pin, di workspace 2
- PENTING: rule 'pin' DIHAPUS dari hyprland.conf. 'pin' bikin window muncul
  di SEMUA workspace & gak bisa dipindah -> jangan dipakai lagi.
- ML tampil fullscreen di dalam Android (policy_control immersive.full=*)
- Window di Hyprland TIDAK fullscreen (biar bisa pindah workspace)

## RESOLUSI ANDROID (PENTING - bikin tampilan gak offset)
Resolusi Android yang BENAR diatur di:
  /var/lib/waydroid/waydroid.cfg  -> [properties]
    persist.waydroid.width = 1600
    persist.waydroid.height = 900
Lalu WAJIB restart container penuh (systemctl stop/start + kill lxc).
- JANGAN pakai `adb shell wm size` -> itu cuma "override" yang bikin
  konten offset + black bar besar (kejadian 2026-09-25).
- Window Hyprland HARUS sama persis (1600x900) -> koordinat klik 1:1.
- density 240 (tablet), immersive.full=* (sembunyikan status bar).

## CONTAINER NYANGKUT (troubleshooting)
Kalau "Container service is already running" tapi STOPPED:
  sudo rmdir /sys/fs/cgroup/lxc.monitor.waydroid
  sudo rmdir /sys/fs/cgroup/lxc.payload.waydroid
  sudo pkill -9 -f "waydroid container"; sudo pkill -9 -f lxc-start
  sudo systemctl reset-failed waydroid-container; sudo systemctl start waydroid-container
Kalau FROZEN: sudo lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid

## SCRIPT UTAMA: mlbb (open/close)
  mlbb            # buka (start semua + ML)
  mlbb up         # sama
  mlbb down       # tutup ML + waydroid  (mlbb down --all = + sunshine)
  mlbb restart    # down lalu up
  mlbb status     # cek semua komponen
  mlbb ui         # buka UI Android saja
Terpasang di /usr/local/bin/mlbb (executable).
Log: /tmp/mlbb.log
CATATAN: pakai password sudo dari env MLBB_SUDO_PW (default built-in).

## KOREKSI RULE HYPRLAND (penting)
`nofullscreenrequest` TIDAK VALID di Hyprland 0.52.2 -> bikin:
  "Config error ... Invalid rule found: nofullscreenrequest"
dan config gagal parse sehingga rule `size` ikut tidak diterapkan.

YANG BENAR:
  windowrulev2 = suppressevent maximize fullscreen, class:^(Waydroid)$
  windowrulev2 = workspace 4 silent, class:^(Waydroid)$
  windowrulev2 = float, class:^(Waydroid)$
  windowrulev2 = size 1600 900, class:^(Waydroid)$
  windowrulev2 = center, class:^(Waydroid)$

## FULLSCREEN / MAXIMIZE (solusi final)
Masalah lama: window bisa di-maximize (1908x1036) tapi Android tetap 1600x900
-> konten di-stretch + black bar.

AKAR: ukuran Android ditentukan prop `persist.waydroid.width/height`
(dibaca HWC via choose_width_height()). HWC baca prop ini SEBELUM
container start, jadi mengubahnya via `waydroid prop set` SAAT RUNTIME
TIDAK berpengaruh (harus restart container).

SOLUSI (dipakai, terbukti):
1. Set resolusi Android = resolusi layar, di DUA tempat:
   /var/lib/waydroid/waydroid_base.prop
       persist.waydroid.width=1920
       persist.waydroid.height=1080
   /var/lib/waydroid/waydroid.cfg  [properties]
       persist.waydroid.width = 1920
       persist.waydroid.height = 1080
2. wd-reset.sh (restart container) -> Android render 1920x1080
3. Rule hyprland:
       windowrulev2 = workspace 4 silent, class:^(Waydroid)$
       windowrulev2 = fullscreen, class:^(Waydroid)$
4. PENTING: dispatch fullscreen butuh window DIFOKUS dulu.
   Urutan: focuswindow -> fullscreen 0

HASIL: window 1920x1080 fullscreen, Android 1920x1080 -> 1:1, tanpa black bar.

CATATAN: kalau ganti monitor/resolusi, ubah prop di 2 file itu + wd-reset.

## SCRIPT UTAMA: mlbb (SEMUA dalam 1 script)
  mlbb                    # = mlbb up (buka + jalankan ML)
  mlbb up                 # buka
  mlbb down [--all]       # tutup (--all = + sunshine)
  mlbb restart            # down lalu up (BERAT - hati2 kalau laptop lemah)
  mlbb status             # status semua komponen
  mlbb ui                 # buka UI Android saja
  mlbb latency on         # optimasi latency (power_save off, cpu, igpu)
  mlbb latency off        # kembalikan
  mlbb latency status     # cek wifi/ping + saran bitrate
  mlbb net                # tampilkan IP + cara konek Artemis
  mlbb net addr           # IP saja

CATATAN: mlbb-net & mlbb-latency script terpisah sudah DIHAPUS,
semua digabung ke /usr/local/bin/mlbb.

## HELP
  mlbb help  (atau -h / --help)  -> penjelasan lengkap tiap perintah
