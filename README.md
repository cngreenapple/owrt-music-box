# 🎵 ST4-PLAYER: Audiophile-Grade Music Server for OpenWrt

Turn your idle OpenWrt Router or Set-Top Box (STB) into a High-End, Bit-Perfect Music Streamer. 

ST4-PLAYER is a lightweight, Dockerized music player tailored specifically for OpenWrt environments. It bypasses the standard Linux audio resampling, delivering pure, untouched audio data directly to your USB DAC. Combined with seamless Bluetooth A2DP support and a smart local library manager, it's the ultimate audio engine for your homelab.

---

## ✨ Key Features

* 🎧 **Bit-Perfect Audio Output:** Delivers pure, untouched digital audio (e.g., 24-bit/96kHz) directly to your USB DAC (like JadeAudio JA11) without system resampling.
* 📡 **Bluetooth A2DP Support:** Custom integrated `bluealsa` allows seamless pairing and streaming to your TWS or Bluetooth Speakers right from the Web UI.
* 🗂️ **Smart Background Scanner:** Asynchronous deep-scanning of your internal/external HDDs (`/mnt`). Automatically extracts ID3 tags (Title, Artist, Album) using `mutagen` and stores them in a lightning-fast SQLite WAL-mode database. Resilient against corrupted files.
* 🌐 **Responsive Web UI:** Control your playback, manage queues, browse folders, and pair Bluetooth devices from any browser.
* ☁️ **YouTube Music & Lyrics API:** Integrated with `ytmusicapi` for cloud streaming and `LRCLIB` for real-time synced lyrics.
* 🐳 **Fully Dockerized:** Runs in an isolated, lightweight Debian container, keeping your OpenWrt host perfectly clean.

---

## 🛠️ Prerequisites

1.  **Hardware:** An OpenWrt Router/STB with a USB port.
2.  **Audio Output:** A USB DAC (Digital-to-Analog Converter) or a Bluetooth Audio Device.
3.  **Software:** OpenWrt with Internet access.

---

## 🚀 Installation Guide

### Step 0: Install OpenWrt Dependencies
Before running anything, make sure your OpenWrt host has the necessary hardware drivers and tools installed. Run this in your OpenWrt SSH terminal:

```bash
opkg update
opkg install kmod-usb-audio bluez-daemon dockerd docker docker-compose git git-http
```
**What are these for?**
* `kmod-usb-audio`: Essential kernel module to detect your USB DAC.
* `bluez-daemon`: The core Bluetooth service for the host.
* `dockerd` & `docker-compose`: To run and manage the ST4-PLAYER container.
* `git` & `git-http`: To clone this repository from GitHub.

Make sure to start and enable the services after installation:
```bash
/etc/init.d/dockerd enable && /etc/init.d/dockerd start
/etc/init.d/bluetoothd enable && /etc/init.d/bluetoothd start
```

### Step 1: Host Preparation (CRITICAL FOR BLUETOOTH)
Because Docker containers are isolated, OpenWrt's security policy (D-Bus) will block the container from routing audio to Bluetooth devices. You **must** create a policy to allow `bluealsa` to communicate with the host's Bluetooth daemon.

Run this directly on your **OpenWrt Host Terminal (SSH)** (NOT inside Docker):

```bash
# 1. Create D-Bus permission for Docker's bluealsa
cat << 'EOF' > /etc/dbus-1/system.d/bluealsa.conf
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "[http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd](http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd)">
<busconfig>
  <policy user="root">
    <allow own="org.bluealsa"/>
    <allow send_destination="org.bluealsa"/>
  </policy>
  <policy context="default">
    <allow send_destination="org.bluealsa"/>
  </policy>
</busconfig>
EOF

# 2. Reload services to apply changes
/etc/init.d/dbus reload
/etc/init.d/bluetoothd restart
```

### Step 2: Clone & Build the Container
Now, clone this repository and fire up Docker Compose.

```bash
git clone https://github.com/st4ngkudut/ST4-Player-OpenWrt.git
cd ST4-Player-OpenWrt

# Build the image and run in detached mode
docker-compose up -d --build
```

> **Note:** The `docker-compose.yml` mounts `/dev/snd` and `/var/run/dbus` which are absolutely necessary for hardware ALSA access and Bluetooth functionality.

---

## 🖥️ OpenWrt LuCI Integration (Optional but Recommended)

Want to access ST4-PLAYER directly from your OpenWrt admin panel? Run this snippet on your OpenWrt SSH to create a dedicated top-level menu in LuCI:

```bash
cat <<'EOF' >/usr/lib/lua/luci/controller/st4player.lua
module("luci.controller.st4player", package.seeall)
function index()
    entry({"admin", "st4player"}, template("st4player"), _("ST4-PLAYER"), 90).leaf=true
end
EOF

cat <<'EOF' >/usr/lib/lua/luci/view/st4player.htm
<%+header%>
<div class="cbi-map">
    <iframe id="st4player" style="width: 100%; min-height: 90vh; border: none; border-radius: 2px;"></iframe>
</div>
<script type="text/javascript">
    document.getElementById("st4player").src = window.location.protocol + "//" + window.location.hostname + ":5000";
</script>
<%+footer%>
EOF

# Clear LuCI cache
rm -rf /tmp/luci-*
```
Refresh your LuCI Web Interface, and you will see the **ST4-PLAYER** tab right next to System and Network!

---

## 📖 Usage

1.  **Accessing:** Open `http://<your-router-ip>:5000` or use the LuCI menu.
2.  **Scanning Library:** Go to the File Manager, navigate to your external HDD mount point (e.g., `/mnt/sda1/Music`), and click **Scan**. Let it run in the background.
3.  **Bluetooth Pairing:** Ensure your TWS/Speaker is in pairing mode. Go to the Bluetooth tab, click **Scan**, and hit **Connect**. The system handles the Agent, Pair, Trust, and A2DP routing automatically.

---

## ⚙️ Tech Stack
* **Backend:** Python 3.11 (Flask)
* **Audio Engine:** MPV & BlueALSA
* **Database:** SQLite3 (WAL Mode for high concurrency)
* **Metadata:** Mutagen

## 📝 License
This project is open-source and available under the MIT License. Feel free to fork, modify, and build upon it!
