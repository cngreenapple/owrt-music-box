#!/bin/bash

# ==================================================
# OWRT-MUSIC-BOX Installer for OpenWrt via Entware
# ==================================================
# This script installs OWRT-MUSIC-BOX (music server)
# directly on OpenWrt aarch64 WITHOUT Docker.
#
# Requires: OpenWrt aarch64, ~500MB free disk space
# ==================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║       OWRT-MUSIC-BOX OpenWrt Installer       ║"
echo "║           (via Entware - No Docker)          ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# --- Step 1: Detect Architecture ---
echo -e "${YELLOW}[1/8] Detecting architecture...${NC}"
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo -e "${RED}Error: This script supports aarch64 only (detected: $ARCH)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Architecture: $ARCH${NC}"

# --- Step 2: Install Entware ---
echo -e "${YELLOW}[2/8] Installing Entware...${NC}"

# Check if Entware is already installed
if [ -f /opt/bin/opkg ]; then
    echo -e "${GREEN}✓ Entware already installed${NC}"
else
    # Remove old entware if partially installed
    rm -rf /opt/* 2>/dev/null || true

    # Create /opt mount
    mkdir -p /opt
    
    # Check if /opt is a mount point, if not bind mount
    if ! mountpoint -q /opt 2>/dev/null; then
        # Use overlay on internal disk - mount bind /opt to a directory on /overlay
        mkdir -p /overlay/opt
        mount --bind /overlay/opt /opt
        # Add to fstab for persistence
        if ! grep -q "/overlay/opt" /etc/fstab 2>/dev/null; then
            echo "/overlay/opt /opt none bind 0 0" >> /etc/fstab
        fi
    fi

    # Download and run Entware installer
    cd /tmp
    # Determine correct Entware URL based on kernel version
    KERNEL_VERSION=$(uname -r | cut -d. -f1-2)
    case "$KERNEL_VERSION" in
        6.1|6.6|6.12) ENTWARE_ARCH="aarch64-5.10" ;;
        5.15|5.10)     ENTWARE_ARCH="aarch64-5.10" ;;
        5.4)           ENTWARE_ARCH="aarch64-5.10" ;;
        *)             ENTWARE_ARCH="aarch64-5.10" ;;
    esac
    ENTWARE_URL="https://bin.entware.net/${ENTWARE_ARCH}/installer/entware_install.sh"
    echo -e "${YELLOW}  Using Entware URL: ${ENTWARE_URL}${NC}"
    wget -O entware_install.sh "$ENTWARE_URL"
    chmod +x entware_install.sh
    sh entware_install.sh
    
    echo -e "${GREEN}✓ Entware installed${NC}"
fi

# --- Step 3: Setup Entware PATH ---
echo -e "${YELLOW}[3/8] Setting up Entware PATH...${NC}"

# Add Entware to PATH in profile
if ! grep -q "/opt/bin" /etc/profile 2>/dev/null; then
    cat >> /etc/profile << 'EOF'

# Entware
export PATH="/opt/bin:/opt/sbin:$PATH"
export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"
EOF
fi

# Export for current session
export PATH="/opt/bin:/opt/sbin:$PATH"
export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"

# Also add to /root/.profile for SSH sessions
if [ -f /root/.profile ]; then
    if ! grep -q "/opt/bin" /root/.profile 2>/dev/null; then
        cat >> /root/.profile << 'EOF'

# Entware
export PATH="/opt/bin:/opt/sbin:$PATH"
export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"
EOF
    fi
fi

# Create rc.func for Entware startup on boot (for OpenWrt)
cat > /etc/init.d/entware << 'INITEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=15

start() {
    # Mount /opt if not mounted
    if ! mountpoint -q /opt 2>/dev/null; then
        mkdir -p /overlay/opt /opt
        mount --bind /overlay/opt /opt
    fi
    
    # Start Entware services
    /opt/etc/init.d/rc.unslung start
}

stop() {
    /opt/etc/init.d/rc.unslung stop
}

restart() {
    stop
    start
}
INITEOF
chmod +x /etc/init.d/entware
/etc/init.d/entware enable

echo -e "${GREEN}✓ Entware PATH configured${NC}"

# --- Step 4: Update opkg & Install Packages via Entware ---
echo -e "${YELLOW}[4/8] Installing packages via Entware opkg...${NC}"

/opt/bin/opkg update

/opt/bin/opkg install \
    mpv \
    mpv-config \
    python3 \
    python3-pip \
    python3-requests \
    python3-urllib3 \
    python3-chardet \
    python3-certifi \
    python3-idna \
    ffmpeg \
    ffprobe \
    alsa-utils \
    alsa-lib \
    bluez-alsa \
    bluez-libs \
    socat \
    procps-ng-pkill \
    coreutils-nohup \
    ca-certificates

echo -e "${GREEN}✓ Core packages installed${NC}"

# --- Step 5: Install Python pip packages ---
echo -e "${YELLOW}[5/8] Installing Python pip packages...${NC}"

/opt/bin/pip3 install --upgrade pip
/opt/bin/pip3 install flask ytmusicapi mutagen

echo -e "${GREEN}✓ Python packages installed${NC}"

# --- Step 6: Install yt-dlp ---
echo -e "${YELLOW}[6/8] Installing yt-dlp...${NC}"

/opt/bin/pip3 install yt-dlp

echo -e "${GREEN}✓ yt-dlp installed${NC}"

# --- Step 7: Setup OWRT-MUSIC-BOX ---
echo -e "${YELLOW}[7/8] Setting up OWRT-MUSIC-BOX...${NC}"

APP_DIR="/opt/owrt-music-box"

# Determine script directory (where this script is running from)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Copy project files - prefer local files (from git clone), fallback to download
if [ -f "$SCRIPT_DIR/app.py" ] && [ -f "$SCRIPT_DIR/library.py" ]; then
    echo -e "${GREEN}  Copying files from local directory: ${SCRIPT_DIR}${NC}"
    
    # Copy Python files
    cp "$SCRIPT_DIR/app.py" "$APP_DIR/app.py"
    cp "$SCRIPT_DIR/library.py" "$APP_DIR/library.py"
    cp "$SCRIPT_DIR/bt_manager.py" "$APP_DIR/bt_manager.py" 2>/dev/null || true
    
    # Copy shell scripts
    cp "$SCRIPT_DIR/play.sh" "$APP_DIR/play.sh" 2>/dev/null || true
    cp "$SCRIPT_DIR/toggle_output.sh" "$APP_DIR/toggle_output.sh" 2>/dev/null || true
    
    # Copy static assets
    cp -r "$SCRIPT_DIR/static/css"/* "$APP_DIR/static/css/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR/static/js"/* "$APP_DIR/static/js/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR/static/img"/* "$APP_DIR/static/img/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR/static/webfonts"/* "$APP_DIR/static/webfonts/" 2>/dev/null || true
    cp "$SCRIPT_DIR/static/manifest.json" "$APP_DIR/static/manifest.json" 2>/dev/null || true
    cp "$SCRIPT_DIR/static/sw.js" "$APP_DIR/static/sw.js" 2>/dev/null || true
    
    # Copy templates
    cp "$SCRIPT_DIR/templates/index.html" "$APP_DIR/templates/index.html" 2>/dev/null || true
    
    echo -e "${GREEN}  Local files copied successfully${NC}"
else
    echo -e "${YELLOW}  Local project files not found, downloading from GitHub...${NC}"
    
    cd "$APP_DIR"
    GITHUB_BASE="https://raw.githubusercontent.com/cngreenapple/owrt-music-box/main"
    
    # Download Python files
    wget -q "$GITHUB_BASE/app.py" -O app.py
    wget -q "$GITHUB_BASE/library.py" -O library.py
    wget -q "$GITHUB_BASE/bt_manager.py" -O bt_manager.py
    
    # Download shell scripts
    wget -q "$GITHUB_BASE/play.sh" -O play.sh
    wget -q "$GITHUB_BASE/toggle_output.sh" -O toggle_output.sh
    
    # Download static files
    wget -q "$GITHUB_BASE/static/manifest.json" -O static/manifest.json
    wget -q "$GITHUB_BASE/static/sw.js" -O static/sw.js
    wget -q "$GITHUB_BASE/static/css/style.css" -O static/css/style.css 2>/dev/null || true
    wget -q "$GITHUB_BASE/static/js/script.js" -O static/js/script.js 2>/dev/null || true
    wget -q "$GITHUB_BASE/templates/index.html" -O templates/index.html 2>/dev/null || true
    
    echo -e "${GREEN}  Files downloaded from GitHub${NC}"
fi

# Create play.sh with Entware paths
cat > "$APP_DIR/play.sh" << 'PLAYEOF'
#!/bin/bash

export PATH="/opt/bin:/opt/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export LC_ALL=C.UTF-8

SOCKET="/tmp/mpv_socket"
MODE_FILE="/opt/owrt-music-box/output_mode"
BP_FILE="/opt/owrt-music-box/bp_mode"
LOG_FILE="/opt/owrt-music-box/mpv_error.log"
VOL_FILE="/opt/owrt-music-box/last_volume"
INPUT_LINK="$1"
START_TIME="${2:-0}"

TARGET_VOL=30

if [ -S "$SOCKET" ]; then
    RAW_VOL=$(echo '{ "command": ["get_property", "volume"] }' | socat - "$SOCKET" 2>/dev/null)
    PARSED_VOL=$(echo "$RAW_VOL" | sed -n 's/.*"data": *\([0-9.]*\).*/\1/p')
    
    if [ -n "$PARSED_VOL" ]; then
        TARGET_VOL=$PARSED_VOL
        echo "$TARGET_VOL" > "$VOL_FILE"
    fi
fi

if [ -z "$PARSED_VOL" ] && [ -f "$VOL_FILE" ]; then
    TARGET_VOL=$(cat "$VOL_FILE")
fi

killall -9 mpv > /dev/null 2>&1 || true
rm -f "$SOCKET"
sleep 0.5

MPV_BIN="/opt/bin/mpv"

AUDIO_DEVICE="alsa/default"
if [ -f "$MODE_FILE" ]; then
    READ_MODE=$(cat "$MODE_FILE")
    if [[ "$READ_MODE" != "" ]]; then
        AUDIO_DEVICE="$READ_MODE"
    fi
fi

EXTRA_ARGS=""
if [[ "$AUDIO_DEVICE" == *"bluealsa"* ]]; then
    EXTRA_ARGS="--ao=alsa --audio-format=s16 --audio-samplerate=44100 --audio-buffer=0.5"
else
    IS_BP="0"
    if [ -f "$BP_FILE" ]; then IS_BP=$(cat "$BP_FILE" | tr -d '[:space:]'); fi
    if [ "$IS_BP" == "1" ]; then
        EXTRA_ARGS="--ao=alsa --no-audio-resample --audio-buffer=0.2"
    else
        EXTRA_ARGS="--ao=alsa"
    fi
fi

if [ -f "$INPUT_LINK" ]; then
    CACHE_OPTS="--cache=yes --demuxer-max-bytes=5M"
    YTDL_OPTS=""
else
    CACHE_OPTS="--cache=yes --demuxer-max-bytes=20M --demuxer-max-back-bytes=10M"
    YTDL_OPTS="--ytdl-format=bestaudio/best --ytdl-raw-options=ignore-errors=,no-check-certificate="
fi

nohup "$MPV_BIN" "$INPUT_LINK" \
    --start="$START_TIME" \
    --input-ipc-server="$SOCKET" \
    --no-video \
    --force-window=no \
    --no-terminal \
    --volume="$TARGET_VOL" \
    --audio-device="$AUDIO_DEVICE" \
    --keep-open=yes \
    --idle=yes \
    --msg-level=all=error \
    $CACHE_OPTS \
    $YTDL_OPTS \
    $EXTRA_ARGS \
    >> "$LOG_FILE" 2>&1 &
disown
PLAYEOF
chmod +x "$APP_DIR/play.sh"

# Create toggle_output.sh
cat > "$APP_DIR/toggle_output.sh" << 'TOGGLEEOF'
#!/bin/bash
DEVICE_STRING="$1"
MODE_FILE="/opt/owrt-music-box/output_mode"

CLEAN_DEV=$(echo "$DEVICE_STRING" | tr -d '\n' | xargs)

if [ -z "$CLEAN_DEV" ]; then
    echo "alsa/default" > "$MODE_FILE"
else
    echo "$CLEAN_DEV" > "$MODE_FILE"
fi

chmod 666 "$MODE_FILE"
TOGGLEEOF
chmod +x "$APP_DIR/toggle_output.sh"

# Fix app.py paths for OpenWrt/Entware
cat > "$APP_DIR/app.py" << 'APPEOF'
from flask import Flask, render_template, request, jsonify
import subprocess
import json
import os
import threading
import time
import socket
import re
import hashlib
import random
import requests
from threading import Lock

try:
    from ytmusicapi import YTMusic
except ImportError:
    YTMusic = None

try:
    from library import lib_mgr
except ImportError:
    lib_mgr = None

app = Flask(__name__)

BASE_DIR = "/opt/owrt-music-box"
MPV_SOCKET = "/tmp/mpv_socket"
PLAYLIST_FILE = os.path.join(BASE_DIR, "playlist.json")
COVER_DIR = os.path.join(BASE_DIR, "static", "covers")
PLAY_SCRIPT = os.path.join(BASE_DIR, "play.sh")
TOGGLE_SCRIPT = os.path.join(BASE_DIR, "toggle_output.sh")
MODE_FILE = os.path.join(BASE_DIR, "output_mode")
DEFAULT_PATH_FILE = os.path.join(BASE_DIR, "default_path.txt")
BP_MODE_FILE = os.path.join(BASE_DIR, "bp_mode")

AUDIO_EXTS = ('.mp3', '.flac', '.wav', '.m4a', '.ogg', '.opus', '.wma', '.aac', '.dsf', '.dff')

state_lock = Lock()
yt_music = YTMusic() if YTMusic else None
needs_restore = False

st4_state = {
    "title": "Ready", 
    "artist": "Waiting...", 
    "album": "",
    "genre": "", 
    "year": "", 
    "tech_info": "",
    "current_time": 0, 
    "total_time": 0, 
    "status": "stopped",
    "volume": 30, 
    "status_output": "jack", 
    "active_preset": "Normal",
    "thumb": "",
    "queue": [],
    "current_index": -1,
    "sleep_target": 0,
    "current_eq_cmd": "",
    "connected_bt_mac": "",
    "connected_bt_name": "",
    "last_play_time": 0,
    "error_count": 0,
    "manual_stop": False
}

af_state = {"eq": "", "balance": "", "crossfeed": ""}

EQ_PRESETS = {
    "Normal": {"f1":0,"f2":0,"f3":0,"f4":0,"f5":0,"f6":0,"f7":0,"f8":0,"f9":0,"f10":0},
    "Bass":   {"f1":7,"f2":6,"f3":5,"f4":3,"f5":0,"f6":0,"f7":0,"f8":-1,"f9":-2,"f10":-3},
    "Rock":   {"f1":5,"f2":3,"f3":1,"f4":-1,"f5":-2,"f6":0,"f7":2,"f8":4,"f9":5,"f10":5},
    "Pop":    {"f1":-1,"f2":1,"f3":3,"f4":4,"f5":4,"f6":2,"f7":0,"f8":1,"f9":2,"f10":2},
    "Jazz":   {"f1":2,"f2":2,"f3":3,"f4":2,"f5":2,"f6":4,"f7":2,"f8":2,"f9":3,"f10":3},
    "Vocal":  {"f1":-3,"f2":-3,"f3":-2,"f4":0,"f5":4,"f6":6,"f7":5,"f8":3,"f9":1,"f10":-1},
    "Dance":  {"f1":8,"f2":7,"f3":4,"f4":0,"f5":0,"f6":2,"f7":4,"f8":5,"f9":6,"f10":5},
    "Acoust": {"f1":1,"f2":2,"f3":2,"f4":3,"f5":4,"f6":4,"f7":3,"f8":2,"f9":3,"f10":2},
    "Party":  {"f1":7,"f2":6,"f3":4,"f4":1,"f5":2,"f6":4,"f7":5,"f8":5,"f9":6,"f10":5},
    "Soft":   {"f1":0,"f2":-1,"f3":-1,"f4":1,"f5":2,"f6":1,"f7":0,"f8":-1,"f9":-2,"f10":-4},
    "Metal":  {"f1":6,"f2":5,"f3":0,"f4":-2,"f5":-3,"f6":0,"f7":3,"f8":6,"f9":7,"f10":7},
    "Classic":{"f1":4,"f2":3,"f3":2,"f4":2,"f5":-1,"f6":-1,"f7":0,"f8":2,"f9":3,"f10":4},
    "RnB":    {"f1":6,"f2":5,"f3":3,"f4":0,"f5":-1,"f6":2,"f7":3,"f8":2,"f9":3,"f10":4},
    "Live":   {"f1":-2,"f2":0,"f3":2,"f4":3,"f5":4,"f6":4,"f7":4,"f8":3,"f9":2,"f10":1},
    "Techno": {"f1":8,"f2":7,"f3":0,"f4":-2,"f5":-2,"f6":0,"f7":2,"f8":4,"f9":6,"f10":6},
    "KZEDCPro": {"f1":6,"f2":5,"f3":3,"f4":1,"f5":0,"f6":0,"f7":-1,"f8":-1,"f9":0,"f10":0}
}

def is_bp_active():
    if os.path.exists(BP_MODE_FILE):
        try:
            with open(BP_MODE_FILE, 'r') as f: return f.read().strip() == "1"
        except: pass
    return False

def update_mpv_filters():
    if is_bp_active():
        mpv_send(["set_property", "af", ""]) 
        mpv_send(["set_property", "volume", 100])
        with state_lock: st4_state["volume"] = 100
        return 
    
    filters = []
    if af_state["balance"]: filters.append(af_state["balance"])
    if af_state["eq"]: filters.append(af_state["eq"])
    if af_state["crossfeed"]: filters.append(af_state["crossfeed"])
    
    cmd_str = ",".join(filters) if filters else ""
    mpv_send(["set_property", "af", cmd_str])

def mpv_send(cmd):
    if not os.path.exists(MPV_SOCKET): return None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.2)
        s.connect(MPV_SOCKET)
        s.send((json.dumps({"command": cmd}) + "\n").encode())
        res = s.recv(8192).decode()
        s.close()
        return json.loads(res).get("data")
    except: return None

def get_yt_thumb(url):
    match = re.search(r"([a-zA-Z0-9_-]{11})", url or "")
    if match: return f"https://img.youtube.com/vi/{match.group(1)}/0.jpg"
    return ""

def extract_local_cover(filepath):
    if not filepath or not os.path.exists(filepath): return ""
    try:
        hash_name = hashlib.md5(filepath.encode('utf-8')).hexdigest()
        cover_filename = f"{hash_name}.jpg"
        save_path = os.path.join(COVER_DIR, cover_filename)
        if os.path.exists(save_path): return f"/static/covers/{cover_filename}"
        if os.path.getsize(filepath) < 102400: return ""
        
        cmd = ["ffmpeg", "-i", filepath, "-an", "-vcodec", "mjpeg", "-q:v", "2", "-frames:v", "1", "-y", save_path]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if os.path.exists(save_path): return f"/static/covers/{cover_filename}"
    except: pass
    return ""

def trigger_play(url):
    global needs_restore
    if os.path.exists(PLAY_SCRIPT):
        with state_lock: 
            st4_state["last_play_time"] = time.time()
            if "http" in url: st4_state["thumb"] = get_yt_thumb(url)
            else: st4_state["thumb"] = ""
            st4_state["status"] = "loading"
            st4_state["manual_stop"] = False 
        
        needs_restore = True
        subprocess.Popen(["/bin/bash", PLAY_SCRIPT, url])

def play_next_in_queue():
    with state_lock:
        if not st4_state["queue"]: return
        time_diff = time.time() - st4_state.get("last_play_time", 0)
        
        if time_diff < 2.0: st4_state["error_count"] += 1
        else: st4_state["error_count"] = 0
            
        if st4_state["error_count"] > 5:
            st4_state["status"] = "stopped"
            st4_state["error_count"] = 0
            return

        next_idx = st4_state["current_index"] + 1
        if next_idx < len(st4_state["queue"]):
            st4_state["current_index"] = next_idx
            next_song = st4_state["queue"][next_idx]
            threading.Thread(target=trigger_play, args=(next_song['link'],)).start()
        else:
            st4_state["status"] = "stopped"

def find_key_insensitive(data, search_keys):
    if not data or not isinstance(data, dict): return ""
    for k in search_keys:
        for data_k, data_v in data.items():
            if data_k.lower() == k.lower(): return data_v
    return ""

def get_connected_bt():
    try:
        output = subprocess.check_output("/opt/bin/bluetoothctl info", shell=True).decode()
        if "Connected: yes" in output:
            mac_match = re.search(r"Device\s+([0-9A-F:]{17})", output)
            name_match = re.search(r"Name:\s+(.*)", output)
            if mac_match:
                return mac_match.group(1), (name_match.group(1) if name_match else "Unknown")
    except: pass
    return None, None

def get_audio_device_string(mode):
    if mode == "jack": return "alsa/default"
    elif mode == "hdmi": return "alsa/plughw:0,0"
    elif mode == "bluetooth":
        mac, name = get_connected_bt()
        if mac: return f"alsa/bluealsa:DEV={mac},PROFILE=a2dp"
        return f"alsa/bluealsa:DEV={st4_state.get('connected_bt_mac','')},PROFILE=a2dp"
    return "alsa/default"

def metadata_worker():
    global st4_state, needs_restore
    last_path = ""
    idle_counter = 0
    
    if not os.path.exists(COVER_DIR): os.makedirs(COVER_DIR, exist_ok=True)
    
    while True:
        try:
            bt_mac, bt_name = get_connected_bt()
            with state_lock:
                st4_state["connected_bt_mac"] = bt_mac or ""
                st4_state["connected_bt_name"] = bt_name or ""

            with state_lock:
                target = st4_state["sleep_target"]
                if target > 0 and time.time() >= target:
                    st4_state["sleep_target"] = 0
                    st4_state["queue"] = []
                    st4_state["current_index"] = -1
                    threading.Thread(target=mpv_send, args=(["stop"],)).start()
            
            mpv_ready = False
            try:
                if mpv_send(["get_property", "idle-active"]) is not None:
                    mpv_ready = True
            except: pass

            if mpv_ready:
                idle_counter = 0 
                path = mpv_send(["get_property", "path"])
                
                if path and (path != last_path or needs_restore):
                    last_path = path
                    needs_restore = False
                    time.sleep(0.5)
                    with state_lock: saved_vol = st4_state["volume"]
                    mpv_send(["set_property", "volume", saved_vol])
                    update_mpv_filters()

                is_eof = mpv_send(["get_property", "eof-reached"])
                is_idle = mpv_send(["get_property", "idle-active"])
                
                if st4_state.get("manual_stop", False):
                    if is_idle:
                        with state_lock: st4_state["manual_stop"] = False
                elif is_eof is True or (is_idle is True and st4_state["status"] == "playing"):
                    play_next_in_queue()
                    time.sleep(1)
                    continue

                final_thumb = ""
                queue_title = "Unknown Title"
                with state_lock:
                    if st4_state["queue"] and st4_state["current_index"] < len(st4_state["queue"]):
                        queue_item = st4_state["queue"][st4_state["current_index"]]
                        final_thumb = queue_item.get('thumb', '')
                        queue_title = queue_item.get('title', 'Unknown Title')
                
                if not final_thumb:
                    if path and "http" in path: 
                        if "googlevideo" not in path: final_thumb = get_yt_thumb(path)
                    else:
                        loc = extract_local_cover(path)
                        if loc: final_thumb = loc
                with state_lock: st4_state["thumb"] = final_thumb

                meta_all = mpv_send(["get_property", "metadata"]) or {}
                mpv_title = mpv_send(["get_property", "media-title"])
                
                final_title = queue_title 
                if mpv_title:
                    is_junk = any(x in mpv_title.lower() for x in ["http", "www.", ".com", "webm&", "googlevideo", "?source"])
                    if not is_junk: final_title = mpv_title
                
                temp_artist = find_key_insensitive(meta_all, ["artist", "performer", "composer"])
                
                if not temp_artist or temp_artist.lower() == "unknown artist":
                    target_title = queue_title if " - " in queue_title else final_title
                    if " - " in target_title:
                        parts = target_title.split(" - ", 1)
                        temp_artist = parts[0].strip()
                        final_title = parts[1].strip()
                    else:
                        temp_artist = "Unknown Artist"
                
                temp_album = find_key_insensitive(meta_all, ["album"]) or ""
                temp_genre = find_key_insensitive(meta_all, ["genre"])
                temp_year = find_key_insensitive(meta_all, ["date", "year", "original_date"])
                
                is_paused = mpv_send(["get_property", "pause"])
                temp_status = "paused" if is_paused else "playing"

                tech_display = []
                raw_codec = mpv_send(["get_property", "audio-codec-name"])
                raw_fmt = mpv_send(["get_property", "audio-params/format"]) 
                raw_rate = mpv_send(["get_property", "audio-params/samplerate"]) 
                raw_br = mpv_send(["get_property", "audio-bitrate"])
                
                codec_str = raw_codec.upper() if raw_codec else "UNK"
                lossy_list = ['MP3', 'AAC', 'VORBIS', 'OPUS', 'WMA', 'WEBM', 'OGG', 'SBC']
                is_lossy = any(x in codec_str for x in lossy_list)
                
                bit_depth = ""
                if raw_fmt:
                    if 's16' in raw_fmt: bit_depth = "16bit"
                    elif 's24' in raw_fmt: bit_depth = "24bit"
                    elif 's32' in raw_fmt or 'float' in raw_fmt: bit_depth = "32bit"
                    elif 'u8' in raw_fmt: bit_depth = "8bit"
                    elif 'dsd' in raw_fmt: bit_depth = "1bit (DSD)"

                freq_str = ""
                sample_rate_val = 0
                if raw_rate:
                    try:
                        sample_rate_val = float(raw_rate)
                        freq_str = f"{sample_rate_val/1000:g}kHz"
                    except: pass

                bitrate_str = ""
                final_bitrate_val = 0
                if raw_br and int(raw_br) > 0:
                    final_bitrate_val = int(raw_br)
                else:
                    try:
                        f_size = mpv_send(["get_property", "file-size"])
                        f_dur = mpv_send(["get_property", "duration"])
                        if f_size and f_dur and float(f_dur) > 0:
                            final_bitrate_val = (int(f_size) * 8) / float(f_dur)
                    except: pass
                
                if final_bitrate_val > 0:
                    bitrate_str = f"{int(final_bitrate_val/1000)}kbps"

                quality_badge = ""
                if is_lossy:
                    quality_badge = "Lossy"
                else:
                    if (bit_depth in ["24bit", "32bit"]) or (sample_rate_val > 48000):
                        quality_badge = "Hi-Res"
                    else:
                        quality_badge = "Lossless"

                tech_display.append(codec_str)
                if bitrate_str: tech_display.append(bitrate_str)
                if freq_str: tech_display.append(freq_str)
                if not is_lossy and bit_depth: tech_display.append(bit_depth) 
                tech_display.append(quality_badge)

                temp_info = " \u2022 ".join(tech_display)
                
                with state_lock:
                    st4_state.update({
                        "title": final_title,
                        "artist": temp_artist, "album": temp_album,
                        "genre": temp_genre, "year": temp_year,
                        "status": temp_status,
                        "tech_info": temp_info,
                        "current_time": mpv_send(["get_property", "time-pos"]) or 0,
                        "total_time": mpv_send(["get_property", "duration"]) or 0
                    })
                    val_vol = mpv_send(["get_property", "volume"])
                    if val_vol is not None: st4_state["volume"] = val_vol
            else:
                idle_counter += 1
                if idle_counter == 5:
                    with state_lock: st4_state["status"] = "stopped"
                if idle_counter == 15 and st4_state["status"] != "stopped":
                    play_next_in_queue()
                    
        except Exception as e: pass
        time.sleep(1)

threading.Thread(target=metadata_worker, daemon=True).start()

@app.route('/')
def index(): return render_template('index.html')

@app.route('/status')
def status():
    with state_lock:
        resp = st4_state.copy()
        target = resp.get("sleep_target", 0)
        if target > 0:
            remaining = int(target - time.time())
            if remaining > 0:
                resp["timer_display"] = f"{int(remaining/60)+1}m"
                resp["timer_active"] = True
            else:
                resp["timer_display"] = "OFF"
                resp["timer_active"] = False
        else:
            resp["timer_display"] = "OFF"
            resp["timer_active"] = False
        return jsonify(resp)

@app.route('/get_lyrics')
def get_lyrics():
    with state_lock:
        artist = st4_state.get("artist", "")
        title = st4_state.get("title", "")
    
    if not title: return jsonify({"error": "No track info"})

    clean_title = re.sub(r"\(.*?\)|\[.*?\]|【.*?】", "", title).strip()
    headers = {"User-Agent": "ST4Player/1.0"}
    
    try:
        if not artist or artist == "Unknown Artist":
            url = "https://lrclib.net/api/search"
            resp = requests.get(url, params={"q": clean_title}, headers=headers, timeout=5)
            data = resp.json()
            if data and isinstance(data, list) and len(data) > 0:
                best_match = data[0]
                if best_match.get('syncedLyrics'): return jsonify({"type": "synced", "lyrics": best_match['syncedLyrics']})
                elif best_match.get('plainLyrics'): return jsonify({"type": "plain", "lyrics": best_match['plainLyrics']})
            return jsonify({"error": "Not found"})

        url = "https://lrclib.net/api/get"
        params = {"artist_name": artist, "track_name": clean_title}
        resp = requests.get(url, params=params, headers=headers, timeout=5)
        
        if resp.status_code == 404:
            url_search = "https://lrclib.net/api/search"
            resp_search = requests.get(url_search, params={"q": f"{artist} {clean_title}"}, headers=headers, timeout=5)
            data_search = resp_search.json()
            if data_search and isinstance(data_search, list) and len(data_search) > 0:
                best_match = data_search[0]
                if best_match.get('syncedLyrics'): return jsonify({"type": "synced", "lyrics": best_match['syncedLyrics']})
                elif best_match.get('plainLyrics'): return jsonify({"type": "plain", "lyrics": best_match['plainLyrics']})
            return jsonify({"error": "Not found"})
            
        data = resp.json()
        if data.get('syncedLyrics'): return jsonify({"type": "synced", "lyrics": data['syncedLyrics']})
        elif data.get('plainLyrics'): return jsonify({"type": "plain", "lyrics": data['plainLyrics']})
        else: return jsonify({"error": "Not found"})
            
    except Exception as e:
        return jsonify({"error": str(e)})

@app.route('/bt/scan')
def bt_scan():
    try:
        subprocess.run("/opt/bin/bluetoothctl scan off", shell=True)
        subprocess.run("/opt/bin/bluetoothctl power on", shell=True)
        subprocess.run("timeout 10s /opt/bin/bluetoothctl scan on", shell=True)
        
        out = subprocess.check_output("/opt/bin/bluetoothctl devices", shell=True).decode()
        devices = []
        matches = re.findall(r"Device\s+([0-9A-F:]{17})\s+(.+)", out)
        for mac, name in matches:
            clean_name = name.strip()
            if clean_name.replace("-", ":") != mac: 
                devices.append({'mac': mac, 'name': clean_name})
        return jsonify(devices)
    except: return jsonify([])

@app.route('/bt/connect')
def bt_connect():
    mac = request.args.get('mac')
    if not mac or ";" in mac: return jsonify({"status":"error"})
    
    try:
        subprocess.run("pgrep bluealsa || /opt/bin/bluealsa &", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1) 
        
        subprocess.run("/opt/bin/bluetoothctl agent on", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run("/opt/bin/bluetoothctl default-agent", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        subprocess.run(["/opt/bin/bluetoothctl", "pair", mac], timeout=15, check=False)
        subprocess.run(["/opt/bin/bluetoothctl", "trust", mac], check=False)
        
        subprocess.run(["/opt/bin/bluetoothctl", "connect", mac], timeout=10, check=False)
        
        time.sleep(2)
        
        info = subprocess.check_output(f"/opt/bin/bluetoothctl info {mac}", shell=True, text=True)
        
        if "Connected: yes" in info:
            dev_name = "Bluetooth Device"
            m = re.search(r"Name:\s+(.*)", info)
            if m: dev_name = m.group(1)

            dev_str = f"alsa/bluealsa:DEV={mac},PROFILE=a2dp"
            mpv_send(["set_property", "audio-device", dev_str])
            with open(MODE_FILE, "w") as f: f.write(dev_str)
            
            with state_lock:
                st4_state["connected_bt_mac"] = mac
                st4_state["connected_bt_name"] = dev_name
                st4_state["status_output"] = "bluetooth"
                
            return jsonify({"status":"ok", "name": dev_name})
        else:
            return jsonify({"status":"failed", "info": "Gagal terhubung. Coba restart TWS/Speaker lalu coba lagi."})
            
    except Exception as e: 
        return jsonify({"status":"error", "info": str(e)})

@app.route('/bt/disconnect')
def bt_disconnect():
    mac = request.args.get('mac')
    if mac: subprocess.run(["/opt/bin/bluetoothctl", "disconnect", mac])
    return jsonify({"status":"ok"})

@app.route('/control/bitperfect')
def toggle_bitperfect():
    current = "0"
    if os.path.exists(BP_MODE_FILE):
        try:
            with open(BP_MODE_FILE, 'r') as f: current = f.read().strip()
        except: pass
    
    new_state = "1" if current == "0" else "0"
    with open(BP_MODE_FILE, 'w') as f: f.write(new_state)
    update_mpv_filters()
    
    if new_state == "0":
        mpv_send(["set_property", "volume", 30])
        with state_lock: st4_state["volume"] = 30

    return jsonify({"status": "ok", "bitperfect": new_state == "1"})

@app.route('/get_bitperfect')
def get_bitperfect():
    active = False
    if os.path.exists(BP_MODE_FILE):
        with open(BP_MODE_FILE, 'r') as f: active = f.read().strip() == "1"
    return jsonify({"active": active})

@app.route('/control/crossfeed')
def toggle_crossfeed():
    state = request.args.get('state', 'on')
    af_state["crossfeed"] = "lavfi=[bs2b=profile=cmoy]" if state == 'on' else ""
    update_mpv_filters()
    return jsonify({"status": "ok", "crossfeed": state == 'on'})

@app.route('/get_crossfeed')
def get_crossfeed():
    return jsonify({"active": len(af_state["crossfeed"]) > 0})

@app.route('/control/jump')
def jump_to_index():
    try:
        idx = int(request.args.get('index', -1))
        with state_lock:
            if 0 <= idx < len(st4_state["queue"]):
                st4_state["current_index"] = idx
                song = st4_state["queue"][idx]
                st4_state["error_count"] = 0
                threading.Thread(target=trigger_play, args=(song['link'],)).start()
                return jsonify({"status": "ok", "title": song['title']})
    except: pass
    return jsonify({"error": "invalid index"})

@app.route('/play', methods=['GET', 'POST'])
def play():
    url = request.args.get('url') or request.form.get('link')
    mode = request.args.get('mode', 'play_now')
    title = request.args.get('title', 'Unknown Title')
    if not url: return jsonify({"error": "no url"})
    song_obj = {'link': url, 'title': title}
    
    with state_lock:
        if mode == 'play_now':
            if os.path.exists(url) and os.path.isfile(url):
                folder_path = os.path.dirname(url)
                try:
                    folder_files = [f for f in os.listdir(folder_path) if f.lower().endswith(AUDIO_EXTS)]
                    folder_files.sort(key=lambda x: x.lower())
                    new_queue = []
                    target_index = 0
                    for idx, fname in enumerate(folder_files):
                        full_path = os.path.join(folder_path, fname)
                        new_queue.append({'link': full_path, 'title': fname})
                        if full_path == url: target_index = idx
                    st4_state["queue"] = new_queue
                    st4_state["current_index"] = target_index
                except:
                    st4_state["queue"] = [song_obj]; st4_state["current_index"] = 0
            elif yt_music and ("youtube.com" in url or "youtu.be" in url):
                st4_state["queue"] = [song_obj]; st4_state["current_index"] = 0
                try:
                    match = re.search(r"(?:v=|\/)([0-9A-Za-z_-]{11})", url)
                    video_id = match.group(1) if match else None
                    if video_id:
                        data = yt_music.get_watch_playlist(videoId=video_id, limit=20)
                        if 'tracks' in data:
                            new_queue = []
                            for t in data['tracks']:
                                vid = t.get('videoId')
                                if vid:
                                    t_artist = t['artists'][0]['name'] if 'artists' in t and t['artists'] else ""
                                    full_title = f"{t_artist} - {t['title']}" if t_artist else t['title']
                                    new_queue.append({'link': f"https://music.youtube.com/watch?v={vid}", 'title': full_title})
                            if new_queue: st4_state["queue"] = new_queue; st4_state["current_index"] = 0
                except: pass
            else:
                st4_state["queue"] = [song_obj]; st4_state["current_index"] = 0
            
            st4_state["error_count"] = 0
            threading.Thread(target=trigger_play, args=(url,)).start()
        elif mode == 'enqueue':
            st4_state["queue"].append(song_obj)
            if st4_state["status"] == "stopped" and len(st4_state["queue"]) == 1:
                st4_state["current_index"] = 0
                threading.Thread(target=trigger_play, args=(url,)).start()
    return jsonify({"status": "ok", "mode": mode, "queue_len": len(st4_state["queue"])})

@app.route('/control/<action>')
def control(action):
    if action == "pause": mpv_send(["cycle", "pause"])
    elif action == "stop":
        mpv_send(["stop"])
        with state_lock:
            st4_state["status"] = "stopped"
            st4_state["queue"] = []
            st4_state["current_index"] = -1
            st4_state["manual_stop"] = True
    elif action == "next": play_next_in_queue()
    elif action == "prev":
        with state_lock:
            if st4_state["current_index"] > 0:
                st4_state["current_index"] -= 1
                prev_song = st4_state["queue"][st4_state["current_index"]]
                trigger_play(prev_song['link'])
            else: mpv_send(["seek", 0, "absolute"])
    elif action == "shuffle":
        with state_lock:
            if len(st4_state["queue"]) > 1:
                current_song = st4_state["queue"][st4_state["current_index"]]
                random.shuffle(st4_state["queue"])
                for idx, song in enumerate(st4_state["queue"]):
                    if song['link'] == current_song['link']:
                        st4_state["current_index"] = idx; break
        return jsonify({"status": "shuffled"})
    elif action == "volume":
        try: 
            v = int(request.args.get('val', 30))
            mpv_send(["set_property", "volume", v])
            with state_lock: st4_state["volume"] = v
        except: pass
    elif action == "seek":
        try: mpv_send(["seek", float(request.args.get('val', 0)), "absolute-percent"])
        except: pass
    elif action == "output":
        target = request.args.get('mode') or 'jack'
        dev_string = get_audio_device_string(target)
        mpv_send(["set_property", "audio-device", dev_string])
        if os.path.exists(TOGGLE_SCRIPT): subprocess.run(["/bin/bash", TOGGLE_SCRIPT, dev_string], check=False)
        else:
            with open(MODE_FILE, "w") as f: f.write(dev_string)
        with state_lock: st4_state["status_output"] = target
        return jsonify({"status": "ok", "active": target})
    return jsonify({"status": "ok"})

def generate_fireq_cmd(gains_dict):
    freqs = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    entries = []
    for i in range(1, 11):
        try: val = float(gains_dict.get(f'f{i}', 0))
        except: val = 0.0
        entries.append(f"entry({freqs[i-1]},{val})")
    return f"firequalizer=gain_entry='{';'.join(entries)}'"

@app.route('/control/eq')
def set_eq():
    p = request.args
    gains = {}
    for i in range(1, 11): gains[f'f{i}'] = p.get(f'f{i}', 0)
    cmd_str = generate_fireq_cmd(gains)
    af_state["eq"] = f"lavfi=[{cmd_str}]"
    update_mpv_filters()
    with state_lock: st4_state["current_eq_cmd"] = af_state["eq"]
    return jsonify({"status": "ok"})

@app.route('/control/preset')
def set_preset():
    n = request.args.get('name')
    if n in EQ_PRESETS:
        preset = EQ_PRESETS[n]
        cmd_str = generate_fireq_cmd(preset)
        af_state["eq"] = f"lavfi=[{cmd_str}]"
        update_mpv_filters()
        with state_lock: 
            st4_state["active_preset"] = n
            st4_state["current_eq_cmd"] = af_state["eq"]
        return jsonify(preset)
    return jsonify({"error": "not found"}), 404

@app.route('/queue/list')
def get_queue():
    with state_lock: return jsonify({"queue": st4_state["queue"], "current_index": st4_state["current_index"]})

@app.route('/queue/clear')
def clear_queue():
    with state_lock: st4_state["queue"] = []; st4_state["current_index"] = -1
    return jsonify({"status": "cleared"})

@app.route('/get_files')
def get_files():
    target = request.args.get('path', '/')
    items = []
    
    if target == '/':
        return jsonify([
            {'name': '\U0001f3e0 Internal Storage (/root)', 'path': '/root', 'type': 'dir'},
            {'name': '\U0001f4be External HDD/USB (/mnt)', 'path': '/mnt', 'type': 'dir'}
        ])

    try:
        abs_path = os.path.abspath(target)
        
        if abs_path != '/':
            parent = os.path.dirname(abs_path)
            if abs_path in ['/root', '/mnt']:
                parent = '/'
            items.append({'name': '..', 'path': parent, 'type': 'dir'})
            
        with os.scandir(abs_path) as entries:
            entry_list = list(entries)
            entry_list.sort(key=lambda e: (not e.is_dir(), e.name.lower()))
            
            for entry in entry_list:
                if entry.name.startswith('.'): continue
                if entry.is_dir(): 
                    items.append({'name': entry.name, 'path': entry.path, 'type': 'dir'})
                elif entry.is_file() and entry.name.lower().endswith(AUDIO_EXTS):
                    items.append({'name': entry.name, 'path': entry.path, 'type': 'file'})
    except Exception as e: pass
    return jsonify(items)

@app.route('/search')
def search_yt():
    query = request.args.get('q', '')
    if not query: return jsonify([])
    if not yt_music: return jsonify([])
    try:
        results = yt_music.search(query, filter="videos", limit=30)
        data = []
        for r in results:
            thumb = r['thumbnails'][-1]['url'] if 'thumbnails' in r else ""
            artists = ", ".join([a['name'] for a in r.get('artists', [])])
            data.append({'title': r.get('title'), 'artist': artists, 'duration': r.get('duration',''), 'thumb': thumb, 'link': f"https://music.youtube.com/watch?v={r['videoId']}", 'videoId': r['videoId']})
        return jsonify(data)
    except: return jsonify([])

@app.route('/system/default_path', methods=['GET', 'POST'])
def handle_default_path():
    if request.method == 'POST':
        try:
            data = request.json; new_path = data.get('path', '/root')
            if os.path.exists(new_path):
                with open(DEFAULT_PATH_FILE, 'w') as f: f.write(new_path)
                return jsonify({"status": "ok", "path": new_path})
            else: return jsonify({"error": "Path not found"}), 404
        except Exception as e: return jsonify({"error": str(e)}), 500
    else:
        path = "/root/music"
        if os.path.exists(DEFAULT_PATH_FILE):
            try:
                with open(DEFAULT_PATH_FILE, 'r') as f: path = f.read().strip()
            except: pass
        return jsonify({"path": path})

@app.route('/system/timer')
def set_timer():
    try: minutes = int(request.args.get('min', 0))
    except: minutes = 0
    with state_lock: st4_state["sleep_target"] = (time.time() + minutes*60) if minutes > 0 else 0
    return jsonify({"status": "ok", "timer": minutes})

@app.route('/get_playlist')
def get_playlist():
    if os.path.exists(PLAYLIST_FILE):
        try:
            with open(PLAYLIST_FILE, 'r') as f: return jsonify(json.load(f))
        except: pass
    return jsonify([])

@app.route('/save_playlist', methods=['POST'])
def save_playlist():
    try:
        with open(PLAYLIST_FILE, 'w') as f: json.dump(request.json, f)
        return jsonify({"status": "ok"})
    except: return jsonify({"error": "failed"}), 500

@app.route('/control/balance')
def set_balance():
    try:
        l_vol = float(request.args.get('l', 1.0))
        r_vol = float(request.args.get('r', 1.0))
    except:
        l_vol = 1.0; r_vol = 1.0

    pan_cmd = f"pan=stereo|c0={l_vol:.2f}*c0|c1={r_vol:.2f}*c1"
    
    if l_vol >= 0.99 and r_vol >= 0.99: af_state["balance"] = ""
    else: af_state["balance"] = f"lavfi=[{pan_cmd}]"
    
    update_mpv_filters()
    return jsonify({"status": "ok", "L": l_vol, "R": r_vol})

@app.route('/library/scan')
def scan_library():
    if lib_mgr:
        scan_path = "/root/music"
        if os.path.exists(DEFAULT_PATH_FILE):
            try:
                with open(DEFAULT_PATH_FILE, 'r') as f: scan_path = f.read().strip()
            except: pass
            
        lib_mgr.scan_directory(scan_path)
        return jsonify({"status": "started", "path": scan_path})
    return jsonify({"status": "disabled"})

@app.route('/library/status')
def library_status():
    if lib_mgr: return jsonify(lib_mgr.get_scan_status())
    return jsonify({"status": "disabled"})

@app.route('/library/tracks')
def library_tracks():
    if not lib_mgr: return jsonify([])
    sort_mode = request.args.get('sort', 'title')
    tracks = lib_mgr.get_all_tracks(sort_mode)
    
    formatted = []
    for t in tracks:
        formatted.append({
            'name': t['title'],
            'path': t['path'],
            'type': 'file',
            'artist': t['artist'],
            'album': t['album'],
            'meta': f"{t['artist']} - {t['album']}"
        })
    return jsonify(formatted)

@app.route('/library/search_db')
def search_db():
    if not lib_mgr: return jsonify([])
    q = request.args.get('q', '')
    if not q: return jsonify([])
    
    results = lib_mgr.search_tracks(q)
    formatted = []
    for t in results:
        formatted.append({
            'title': t['title'],
            'artist': t['artist'],
            'album': t['album'],
            'link': t['path'],
            'thumb': '/static/img/default.png', 
            'is_local': True
        })
    return jsonify(results)

if __name__ == '__main__':
    import subprocess
    subprocess.run("pgrep bluealsa || /opt/bin/bluealsa -p a2dp-source -p a2dp-sink &", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    app.run(host='0.0.0.0', port=2027, debug=False)
APPEOF

# Create default index.html as fallback if template was not copied
if [ ! -f "$APP_DIR/templates/index.html" ]; then
    cat > "$APP_DIR/templates/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OWRT-MUSIC-BOX</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #1a1a2e; color: #eee; }
        h1 { color: #e94560; }
        .loading { font-size: 18px; color: #aaa; }
    </style>
</head>
<body>
    <h1>OWRT-MUSIC-BOX</h1>
    <p class="loading">Web UI is loading...</p>
    <p>If this page persists, re-run: <code>./install_openwrt.sh</code> from the cloned repo.</p>
</body>
</html>
HTMLEOF
fi

# Create D-Bus config for bluealsa
mkdir -p /opt/owrt-music-box/dbus
cat > /opt/owrt-music-box/dbus/bluealsa.conf << 'DBUSEOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="org.bluealsa"/>
    <allow send_destination="org.bluealsa"/>
  </policy>
  <policy context="default">
    <allow send_destination="org.bluealsa"/>
  </policy>
</busconfig>
DBUSEOF

# Make library.py use /opt/owrt-music-box path
sed -i 's|os.path.dirname(os.path.abspath(__file__))|"/opt/owrt-music-box"|g' "$APP_DIR/library.py" 2>/dev/null || true

echo -e "${GREEN}✓ OWRT-MUSIC-BOX files installed${NC}"

# --- Step 8: Create Init Script ---
echo -e "${YELLOW}[8/8] Creating startup script...${NC}"

cat > /etc/init.d/owrt-music-box << 'INITEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=15
USE_PROCD=1

SERVICE_DIR="/opt/owrt-music-box"

start_service() {
    # Ensure /opt is mounted
    if ! mountpoint -q /opt 2>/dev/null; then
        mkdir -p /overlay/opt /opt
        mount --bind /overlay/opt /opt
    fi
    
    # Export Entware paths
    export PATH="/opt/bin:/opt/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
    export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"
    
    # Copy D-Bus config for bluealsa
    if [ -f "$SERVICE_DIR/dbus/bluealsa.conf" ]; then
        cp "$SERVICE_DIR/dbus/bluealsa.conf" /etc/dbus-1/system.d/bluealsa.conf
        /etc/init.d/dbus reload 2>/dev/null || true
    fi
    
    # Start bluealsa if available
    BLUEALSA_BIN="/opt/bin/bluealsa"
    if [ -f "$BLUEALSA_BIN" ]; then
        if ! pgrep bluealsa > /dev/null 2>&1; then
            $BLUEALSA_BIN -p a2dp-source -p a2dp-sink &
            sleep 1
        fi
    fi
    
    # Create output_mode file if not exist
    if [ ! -f "$SERVICE_DIR/output_mode" ]; then
        echo "alsa/default" > "$SERVICE_DIR/output_mode"
    fi
    
    # Start Flask app via procd
    procd_open_instance
    procd_set_param command /opt/bin/python3 "$SERVICE_DIR/app.py"
    procd_set_param respawn 3600 5 5
    procd_set_param env PATH="/opt/bin:/opt/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
    procd_set_param env LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"
    procd_set_param env HOME="/root"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
    
    echo "OWRT-MUSIC-BOX started on port 2027"
}

stop_service() {
    # Stop Flask app
    PID=$(pgrep -f "python3.*app.py" 2>/dev/null || echo "")
    if [ -n "$PID" ]; then
        kill -15 $PID 2>/dev/null || true
    fi
    
    # Stop mpv
    killall -9 mpv 2>/dev/null || true
    
    # Stop bluealsa
    BLUEALSA_PID=$(pgrep bluealsa 2>/dev/null || echo "")
    if [ -n "$BLUEALSA_PID" ]; then
        kill -15 $BLUEALSA_PID 2>/dev/null || true
    fi
    
    rm -f /tmp/mpv_socket
}

restart() {
    stop
    sleep 1
    start
}
INITEOF

chmod +x /etc/init.d/owrt-music-box
/etc/init.d/owrt-music-box enable

echo -e "${GREEN}✓ Init script created and enabled${NC}"

# --- Final Summary ---
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         INSTALLATION COMPLETE!               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}What's installed:${NC}"
echo "  - Entware (package manager for embedded)"
echo "  - mpv, ffmpeg, alsa-utils"
echo "  - bluealsa (Bluetooth A2DP)"
echo "  - Python 3 + Flask + ytmusicapi + mutagen"
echo "  - yt-dlp"
echo "  - OWRT-MUSIC-BOX files in /opt/owrt-music-box/"
echo ""
echo -e "${YELLOW}Usage:${NC}"
echo "  Start OWRT-MUSIC-BOX:  ${GREEN}/etc/init.d/owrt-music-box start${NC}"
echo "  Stop:                 ${GREEN}/etc/init.d/owrt-music-box stop${NC}"
echo "  Restart:              ${GREEN}/etc/init.d/owrt-music-box restart${NC}"
echo "  Auto-start:           ${GREEN}(already enabled)${NC}"
echo ""
echo -e "${YELLOW}Access Web UI:${NC}"
echo "  http://$(ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo '<your-router-ip>'):2027"
echo ""
echo -e "${YELLOW}First run:${NC}"
echo "  Reboot your router, or just run:"
echo "  ${GREEN}/etc/init.d/entware start && /etc/init.d/owrt-music-box start${NC}"
echo ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo "  If Web UI doesn't load, restart the service:"
echo "  ${GREEN}/etc/init.d/owrt-music-box restart${NC}"
echo "  Check logs: ${GREEN}cat /opt/owrt-music-box/mpv_error.log${NC}"
