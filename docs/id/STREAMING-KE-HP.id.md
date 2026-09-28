# Streaming MLBB (Waydroid) ke HP — PANDUAN LENGKAP

Tujuan: laptop yang "main" (render ML), HP cuma jadi **layar + kontrol**.
HP kamu (Android phone) tidak akan panas karena tidak render grafis.

```
[Laptop]                          [HP]
 ML di Waydroid                    Moonlight/Artemis app
        |                                   ^
        v                                   |
  Sunshine (encoder NVENC)  --WiFi-->  decoder HP
```

---

## BAGIAN 1 — Install Sunshine di laptop

Sunshine = server streaming. Pakai NVENC (RTX 2050) buat encode.

### Opsi A: flatpak (paling gampang)
```bash
flatpak install -y flathub dev.lizardbyte.app.Sunshine
```

### Opsi B: AppImage (kalau tidak mau flatpak)
```bash
mkdir -p ~/Apps && cd ~/Apps
# ambil versi terbaru dari github.com/LizardByte/Sunshine/releases
wget https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine.AppImage
chmod +x sunshine.AppImage
```

### Opsi C: dari repo Kali (kalau ada)
```bash
sudo apt install sunshine    # cek dulu: apt-cache policy sunshine
```

---

## BAGIAN 2 — Setup Sunshine

### 2.1 Jalankan pertama kali
```bash
sunshine          # flatpak: flatpak run dev.lizardbyte.app.Sunshine
```

### 2.2 Set username & password web UI
Buka di browser laptop: **https://localhost:47990**
- Bikin username + password (catat!)
- Ini buat akses admin, BUKAN password HP

### 2.3 Tambah aplikasi "Mobile Legends"

Di web UI → **Applications** → **Add New**:

| Field | Isi |
|-------|-----|
| Name | `Mobile Legends` |
| Command | `/usr/local/bin/ml-stream.sh` |
| Working Dir | `<HOME-DIR>` |

Buat script `/usr/local/bin/ml-stream.sh` (isi di bawah) supaya Sunshine
otomatis jalanin Waydroid + ML lalu "menempel" ke game.

### 2.4 Encoder settings (PENTING)
Web UI → **Configuration** → **Audio/Video**:

| Setting | Nilai | Alasan |
|---------|-------|--------|
| Encoder | **NVIDIA NVENC** | pakai RTX 2050 |
| Codec | **HEVC (H.265)** | lebih hemat bitrate |
| Resolution | **1600x900** | samakan dgn Waydroid |
| FPS | **60** | HP-mu 120Hz tapi 60 cukup |
| Bitrate | **20000-30000** kbps | LAN 5GHz |

---

## BAGIAN 3 — Script peluncur ML untuk Sunshine

Buat file `/usr/local/bin/ml-stream.sh`:
```bash
sudo tee /usr/local/bin/ml-stream.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# Dipanggil Sunshine saat HP minta "Mobile Legends"
export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
export WAYLAND_DISPLAY=wayland-1

# 1. pastikan Waydroid + ML jalan
/usr/local/bin/waydroid-nat.sh >/dev/null 2>&1
waydroid status 2>/dev/null | grep -q "Session:.*RUNNING" || {
  nohup waydroid session start >/dev/null 2>&1 &
  sleep 18
}
pgrep -f show-full-ui >/dev/null || {
  setsid waydroid show-full-ui </dev/null >/dev/null 2>&1 &
  sleep 15
}
adb connect 192.168.240.112:5555 >/dev/null 2>&1
adb shell am start -n com.mobile.legends/com.moba.unityplugin.MobaGameMainActivityWithExtractor >/dev/null 2>&1

# 2. buka window Waydroid di workspace 2, ukuran pas
for i in 1 2 3 4 5; do
  ADDR=$(hyprctl clients -j 2>/dev/null | python3 -c \
    "import json,sys
try: print([w['address'] for w in json.load(sys.stdin) if w.get('class')=='Waydroid'][0])
except: pass" 2>/dev/null)
  [ -n "$ADDR" ] && break
  sleep 3
done
hyprctl dispatch setfloating  "address:$ADDR" >/dev/null 2>&1
hyprctl dispatch resizewindowpixel exact 1600 900,"address:$ADDR" >/dev/null 2>&1
hyprctl dispatch movetoworkspace 2,"address:$ADDR" >/dev/null 2>&1

# 3. tunggu ML benar-benar tampil
sleep 45
EOF
sudo chmod +x /usr/local/bin/ml-stream.sh
```

---

## BAGIAN 4 — Firewall (penting!)

Sunshine butuh port terbuka:
```bash
sudo ufw allow 47984/tcp   # HTTPS
sudo ufw allow 47989/tcp   # HTTP
sudo ufw allow 47990/tcp   # Web UI
sudo ufw allow 48010/tcp   # RTSP control
sudo ufw allow 47998:48000/udp   # video/audio stream
```

---

## BAGIAN 5 — Install client di HP

**Pilihan 1: Moonlight (resmi, dari Play Store)**
- Cari "Moonlight Game Streaming" → install
- Bagus, tapi multi-touch terbatas

**Pilihan 2: Artemis (fork Moonlight) — LEBIH BAIK untuk MOBA**
- Download dari GitHub: `github.com/ClassicOldSong/moonlight-android` (Artemis)
- Alasan: **multi-touch lebih baik** → penting buat joystick + skill ML

> Rekomendasi: **Artemis**. ML butuh 2 jari barengan terus.

---

## BAGIAN 6 — Pairing HP ke Laptop

1. **HP & laptop di WiFi yang SAMA** (5GHz, SSID rumah)
2. Buka Moonlight/Artemis di HP → otomatis cari host, atau **Add manually**:
   - IP: **`<IP-LAPTOP>`**
3. Laptop akan tampil PIN di layar → **masukkan PIN itu di HP**
4. Selesai! Sekarang pilih app **"Mobile Legends"**

---

## BAGIAN 7 — Kontrol sentuh

Di dalam Moonlight/Artemis saat main:
- Aktifkan mode **"Touchscreen"** (bukan trackpad/mouse)
- **Multi-touch ON** (di Artemis biasanya otomatis)
- Orientasi: **landscape**

Kalau skill tidak kena:
- Cek **multi-touch** benar-benar aktif
- Kurangi latensi: pakai **5GHz**, dekat router
- Kalau perlu, matikan "optimize game settings"

---

## BAGIAN 8 — Optimasi biar mulus

### Laptop
```bash
cpu-profile performance        # CPU kencang saat streaming
gpu-tune.sh on                 # iGPU freq naik
~/ml-waydroid.sh stop          # pastikan cuma 1: session bersih
```

### Jaringan
| Benar | Salah |
|-------|-------|
| Laptop pakai **kabel LAN** | Laptop WiFi (micro-stutter) |
| HP di **5GHz** | 2.4GHz (lag spike) |
| Dekat router | Lewat banyak tembok |

---

## TROUBLESHOOTING

### "Host tidak ketemu" di HP
```bash
# cek Sunshine jalan
ss -tulnp | grep 4798
# cek firewall
sudo ufw status
# cek IP benar
ip -4 addr show wlan0 | grep inet
```

### Video lag / patah-patah
- Turunin bitrate (30000 → 15000)
- Ganti codec HEVC → H.264
- Pastikan WiFi 5GHz (bukan 2.4)

### Input delay tinggi
- Pakai kabel LAN di laptop
- Dekatkan HP ke router
- Matikan app lain yang pakai internet

### HP tetap panas
- Seharusnya **tidak** — HP cuma decode video
- Kalau tetap panas: turunin FPS (60→30) atau resolusi

---

## REALITA YANG HARUS DITERIMA

- **Input delay tetap ada** (~20-40ms di LAN bagus). Buat ranked tetap kerasa.
- **Multi-touch** di Moonlight standar canggung → pakai Artemis.
- **Risiko ban tetap ada** (Waydroid = environment mencurigakan bagi anti-cheat).
- Streaming ini **paling enak buat main santai**, bukan ranked serius.

---

## RINGKASAN PERINTAH

```bash
# laptop
sunshine                                    # start server
/usr/local/bin/ml-stream.sh                 # test manual
sudo ufw allow 47984/tcp && sudo ufw allow 47989/tcp
sudo ufw allow 47998:48000/udp

# HP
# install Artemis -> Add host <IP-LAPTOP> -> masukkan PIN -> pilih "Mobile Legends"
```

---
# ===== UPDATE: HASIL INSTALL SUNSHINE (2026-09-25) =====

## STATUS: SUDAH TERINSTALL & JALAN

### Yang dipakai
- Sunshine v2026.914.233613 (deb dari GitHub, paket `debiantrixie`)
- Install: `dpkg -i` + trik `equivs` bikin dummy `libminiupnpc18`
  → Kali punya `libminiupnpc21`, dibikin symlink:
  `ln -sf .../libminiupnpc.so.21 .../libminiupnpc.so.18`
- **Encoder: VAAPI via Intel iGPU** (bukan NVENC!)
- **Capture: wlr** (Wayland/Hyprland)

### KENAPA BUKAN NVENC?
Binary Sunshine di-bundle dgn CUDA runtime yg butuh driver > 550.
Driver 550 = CUDA 12.4 → error `cudaErrorInsufficientDriver`.
Intel QuickSync (VAAPI) justru LANCAR + bikin NVIDIA bebas.

### AKAR MASALAH VAAPI: driver salah
`vainfo` nyasar ke "VA-API NVDEC driver" (NVIDIA) yg cuma DECODE (VLD).
FIX: `LIBVA_DRIVER_NAME=iHD` → pakai Intel iHD yg punya `VAEntrypointEncSlice`.

### CONFIG: ~/.config/sunshine/sunshine.conf
    capture = wlr
    encoder = vaapi
    adapter_name = /dev/dri/renderD128
    fps = 60

### SERVICE: ~/.config/systemd/user/sunshine.service
Autostart bareng grafis. Isinya:
    Environment=LIBVA_DRIVER_NAME=iHD
    Environment=WAYLAND_DISPLAY=wayland-1
    ExecStart=/usr/bin/sunshine

### CREDENTIALS WEB UI (https://localhost:47990)
    username: <USERNAME-ANDA>
    password: <PASSWORD-ANDA>

### APP DI SUNSHINE
- "Mobile Legends" -> /usr/local/bin/ml-stream.sh
- ada di ~/.config/sunshine/apps.json

### PORT (firewall INPUT ACCEPT, jadi sudah terbuka)
    47984-47990 tcp, 48010 tcp, 47998-48000 udp

### LANGKAH DI HP
1. Install **Artemis** (fork Moonlight) - multi-touch bagus utk MOBA
2. Add host manual: **<IP-LAPTOP>**
3. Masukkan PIN yg muncul di laptop
4. Pilih "Mobile Legends"

---
# ===== FIX MULTI-TOUCH (2026-09-26) =====

## GEJALA
Tahan joystick ML (jari-1), lalu tap skill (jari-2) -> joystick LEPAS.
Cuma bisa ~2 jari, tidak bisa 3-4 jari.

## AKAR MASALAH (terkonfirmasi)
Android InputDispatcher mencatat:
  "Dropping move event because a pointer for a different device is
   already active in display 0"       (puluhan kali)
Penyebab: Waydroid mendaftarkan DUA device input:
  - wayland_touch   (touch asli dari Sunshine)  -> SUMBER KONFLIK
  - wayland_pointer (mouse virtual, dibuat HWC)
Ketika Hyprland mengirim wl_pointer.motion (karena onTouchDown ->
refocus() -> mouseMoveUnified -> sendPointerMotion), event mouse dan
touch datang bersamaan -> Android membatalkan/mengacak touch points.

Terkonfirmasi juga oleh PR Hyprland #4071:
  "touch events and cursor move events come together and makes
   waydroid not handling touch events correctly"

## SOLUSI (dipakai, TANPA patch binary)
Disable device `wayland_pointer` di Android memakai file IDC.
`libinputreader.so` membaca prop `device.disabled` dari file .idc.

File (ditulis ke overlay, PERSISTEN):
  /var/lib/waydroid/overlay/system/usr/idc/wayland_pointer.idc
Isi:
    device.disabled = 1

Kenapa overlay: rootfs Waydroid read-only (system.img ro). Overlay lowerdir
/var/lib/waydroid/overlay/system ikut ter-merge saat boot -> persisten.

## HASIL (terbukti)
- device wayland_pointer: HILANG (count=0)
- error "Dropping move event...different device": 0 (dulu puluhan)
- wayland_touch tetap ada & berfungsi

## CATATAN
- `persist.waydroid.fake_touch` HARUS off (kalau on, malah melebur touch).
- `native_pen_touch = enabled` di sunshine.conf (bikin device touchscreen).
- udev rule /etc/udev/rules.d/71-sunshine-notablet.rules abaikan Pen Tablet.
- Gesture 3/4 jari Hyprland dimatikan di configs/SystemSettings.conf.

## KALAU MAU BALIKIN (un-disable)
  rm /var/lib/waydroid/overlay/system/usr/idc/wayland_pointer.idc
  lalu wd-reset.sh

## ALIGNMENT WINDOW (PENTING)
JANGAN maximize/fullscreen window Waydroid!
- HWC Waydroid TIDAK resize Android saat window berubah ukuran.
- Kalau window > resolusi Android (mis. 1908x1037 vs 1600x900), konten
  di-STRETCH (bukan letterbox) -> tampilan aneh + black bar.
- Window harus PERSIS = resolusi Android (1:1) supaya tampilan & klik akurat.

Rule hyprland (persisten, bikin tetap 1600x900):
  windowrulev2 = workspace 4 silent, class:^(Waydroid)$
  windowrulev2 = float,    class:^(Waydroid)$
  windowrulev2 = size 1600 900, class:^(Waydroid)$
  windowrulev2 = center,   class:^(Waydroid)$
  windowrulev2 = nofullscreenrequest, class:^(Waydroid)$

`mlbb up` otomatis: reset wm size/density -> baca resolusi Android ->
resize window persis -> center.

Kalau mau ubah ukuran (mis. lebih ringan 1280x720):
1. Set resolusi Android permanen, ATAU
2. adb shell wm size 1280x720 lalu mlbb restart

---
# ===== OPTIMASI LATENCY (2026-09-27) =====

## DIAGNOSA LATENCY TINGGI
1. **Hotspot HP = 2.4 GHz** (freq 2462 MHz, ch 11)
   - Bandwidth kecil (~120-143 Mbit/s) -> bitrate tinggi malah lag
   - Jitter bawaan 2.4GHz lebih tinggi dari 5GHz
2. **WiFi power_save = ON** (default) -> nambah latency & jitter
3. WARP/Tailscale TIDAK berpengaruh (10.x ada di exclude list, trafik lokal
   tetap lewat wlan0 langsung)

## SETUP OPTIMAL: laptop nyambung ke HOTSPOT HP
- HP jadi router; laptop client -> skema paling stabil & simpel (tanpa WiFi publik)
- Pastikan hotspot HP kalau bisa di **5 GHz** (banyak HP punya setting ini!)

## OPTIMASI YANG DITERAPKAN (script mlbb-latency)
  mlbb-latency on      # terapkan
  mlbb-latency status  # cek
  mlbb-latency off     # kembalikan
Yang diubah:
  - `iw dev wlan0 set power_save off`  <- paling ngaruh!
  - `nmcli connection modify <conn> wifi.powersave 2`
  - cpu-profile balanced, gpu-tune on

## TUNING SUNSHINE (~/.config/sunshine/sunshine.conf)
  vaapi_quality = speed     # prioritaskan kecepatan
  vaapi_rc = cbr            # rate control konstan
  qp = 28                   # bitrate lebih kecil
  fec_percentage = 20       # tahan packet loss WiFi
  intra_refresh = 25        # kurangi artefak
  min_threads = 4
(Penting: error 'av1_vaapi' & 'CAP_SYS_ADMIN' di log = TIDAK berbahaya)

## TUNING DI ARTEMIS (HP) — WAJIB, ini yang paling kelihatan
  Video resolution : 1280x720 (2.4GHz) atau 1920x1080 (5GHz)
  FPS              : 60
  Video bitrate    : 8-15 Mbps untuk 2.4GHz (JANGAN 30+)
  Video codec      : H.264 (lebih tahan di 2.4GHz daripada HEVC)
  'Optimize game settings' : ON
  Audio            : stereo, bitrate 128

## CATATAN
- Hotspot HP biasanya kasih IP acak -> cek `mlbb-net` tiap kali.
- Kalau HP punya opsi hotspot 5GHz, AKTIFKAN. Itu peningkatan terbesar.
