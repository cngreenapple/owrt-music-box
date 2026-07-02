# 🎵 OWRT-MUSIC-BOX

Audiophile-Grade Music Server for **OpenWrt** — No Docker required.

Turn your OpenWrt Router/STB (Amlogic S905X, aarch64) into a High-End, Bit-Perfect Music Streamer. Uses **Entware** to install mpv, bluealsa, ffmpeg, and Python directly on your router.

---

## ✨ Features

- 🎧 **Bit-Perfect Audio Output** — Direct USB DAC support without system resampling
- 📡 **Bluetooth A2DP** — Stream to TWS/Speakers via bluealsa + Web UI
- 🗂️ **Local Library Scanner** — Auto-scan HDD/USB, extract ID3 tags via mutagen, store in SQLite
- 🌐 **Responsive Web UI** — Control playback, manage queues, browse files, pair Bluetooth from any browser
- ☁️ **YouTube Music & Lyrics** — Search & stream from YT Music, synced lyrics from LRCLIB
- 🐳 **No Docker** — Runs natively on OpenWrt via Entware (lightweight, direct hardware access)
- 🎛️ **16-Band EQ + Crossfeed + Balance** — lavfi-based DSP filters via mpv

---

## 📋 Requirements

- **Hardware:** OpenWrt Router/STB with **aarch64** CPU (e.g. Amlogic S905X, S905Y, S922X, RK3328, RK3399)
- **RAM:** ≥512MB (1GB+ recommended)
- **Storage:** ~500MB free on internal disk (or USB flash)
- **Audio:** USB DAC or Bluetooth A2DP device
- **OS:** OpenWrt 23.05+ / 24.10+ with kernel ≥5.10

---

## 🚀 Installation

SSH into your OpenWrt device and run:

```bash
# 1. Install git (if not already installed)
opkg update
opkg install git git-http ca-certificates

# 2. Clone the repository
git clone https://github.com/cngreenapple/owrt-music-box.git
cd owrt-music-box

# 3. Run the installer (takes 5-15 minutes)
chmod +x install_openwrt.sh
./install_openwrt.sh
```

The script will:
1. Install **Entware** package manager to `/opt`
2. Install **mpv**, **ffmpeg**, **bluez-alsa**, **alsa-utils**, **Python 3**, **socat**
3. Install Python packages: **flask**, **ytmusicapi**, **mutagen**, **yt-dlp**
4. Copy all files from the cloned repo to **`/opt/owrt-music-box/`**
5. Create **play.sh** and **app.py** with Entware-compatible paths
6. Configure **D-Bus** policy for bluealsa
7. Create init script `/etc/init.d/owrt-music-box` (auto-start on boot)

### After Installation

```bash
# Start the service
/etc/init.d/owrt-music-box start

# Or reboot to start everything automatically
reboot
```

### Access the Web UI

```
http://192.168.1.178:2027
```

---

## 🛠️ Manual Service Control

```bash
/etc/init.d/owrt-music-box start     # Start the server
/etc/init.d/owrt-music-box stop      # Stop
/etc/init.d/owrt-music-box restart   # Restart
/etc/init.d/owrt-music-box enable    # Enable auto-start (default)
/etc/init.d/owrt-music-box disable   # Disable auto-start
```

---

## 📁 Directory Structure

```
/opt/owrt-music-box/
├── app.py              # Flask backend (port 2027)
├── library.py          # Music library scanner (SQLite)
├── bt_manager.py       # Bluetooth helper
├── play.sh             # mpv launcher script
├── toggle_output.sh    # Audio output switcher
├── dbus/
│   └── bluealsa.conf   # D-Bus policy for bluealsa
├── static/
│   ├── css/            # Web UI styles
│   ├── js/             # Web UI scripts
│   ├── img/            # Icons & default cover
│   ├── webfonts/       # Font Awesome icons
│   ├── manifest.json   # PWA manifest
│   └── sw.js           # Service worker
└── templates/
    └── index.html      # Web UI main page
```

---

## 🔧 Tech Stack

| Component | Package | Notes |
|---|---|---|
| **Audio Engine** | `mpv` | via Entware |
| **Bluetooth A2DP** | `bluez-alsa` | D-Bus policy configured |
| **Backend** | Python 3 + Flask | Port 2027 |
| **Audio Processing** | ffmpeg | Cover extraction, metadata |
| **Database** | SQLite | WAL mode for concurrency |
| **Metadata** | mutagen | ID3 tag parsing |
| **YouTube Music** | ytmusicapi + yt-dlp | Streaming & search |

---

## 📝 License

MIT License — feel free to fork, modify, and improve.