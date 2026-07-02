# 🎵 OWRT-MUSIC-BOX

Audiophile-Grade Music Server for **OpenWrt** — No Docker required.

Turn your OpenWrt Router/STB (Amlogic S905X, aarch64) into a Music Streamer. Uses **Entware** to install Python, ffmpeg, and ALSA tools directly on your router.

---

## ✨ Features

- 🌐 **Responsive Web UI** — Control playback, manage queues, browse files from any browser
- 🗂️ **Local Library Scanner** — Auto-scan HDD/USB, extract ID3 tags via mutagen, store in SQLite
- ☁️ **YouTube Music & Lyrics** — Search & stream from YT Music, synced lyrics from LRCLIB
- 🐳 **No Docker** — Runs natively on OpenWrt via Entware (lightweight, direct hardware access)
- 📡 **Bluetooth** — Scan & pair devices via bluetoothctl

---

## 📋 Requirements

- **Hardware:** OpenWrt Router/STB with **aarch64** CPU (e.g. Amlogic S905X)
- **RAM:** ≥512MB (1GB+ recommended)
- **Storage:** ~400MB free on internal disk
- **OS:** OpenWrt 23.05+ / 24.10+ with kernel ≥5.10

---

## 🚀 Installation

SSH into your OpenWrt device and run:

```bash
# 1. Install git
opkg update
opkg install git git-http ca-certificates

# 2. Clone the repository
git clone https://github.com/cngreenapple/owrt-music-box.git
cd owrt-music-box

# 3. Run the installer (takes 5-15 minutes)
chmod +x install_openwrt.sh
./install_openwrt.sh
```

### After Installation

```bash
# Start the service
/etc/init.d/owrt-music-box start

# Access Web UI
http://192.168.1.178:2027
```

---

## 🎵 Installing mpv (Audio Player)

**mpv is NOT available in Entware aarch64 repository.** The Web UI will start without it, but audio playback needs mpv.

### Option 1: Try to download a static binary
```bash
# Try downloading a static mpv build for aarch64
wget -q -O /opt/bin/mpv https://github.com/nickcz/mpv-linux-aarch64/releases/latest/download/mpv
chmod +x /opt/bin/mpv
/etc/init.d/owrt-music-box restart
```

### Option 2: Use mpg123 for basic MP3 playback
```bash
/opt/bin/opkg install mpg123
```

### Option 3: Compile from source (advanced)
```bash
/opt/bin/opkg install gcc make
# Clone mpv and compile (requires ~300MB space)
```

---

## 📁 Directory Structure

```
/opt/owrt-music-box/
├── app.py              # Flask backend (port 2027)
├── library.py          # Music library scanner (SQLite)
├── bt_manager.py       # Bluetooth helper
├── play.sh             # Audio player launcher
├── toggle_output.sh    # Audio output switcher
├── static/             # Web UI assets
└── templates/
    └── index.html      # Web UI main page
```

---

## 🔧 Tech Stack

| Component | Source | Notes |
|---|---|---|
| **Backend** | Python 3 + Flask | via Entware |
| **Audio (optional)** | mpv / mpg123 | Manual install |
| **Bluetooth** | bluez-daemon + bluez-utils | via Entware |
| **FFmpeg** | ffmpeg + ffprobe | via Entware |
| **SQLite** | Python built-in | Music library DB |
| **Metadata** | mutagen | via pip |
| **YouTube Music** | ytmusicapi + yt-dlp | via pip |
| **ALSA** | alsa-utils + alsa-lib | via Entware |

---

## 📝 License

MIT License