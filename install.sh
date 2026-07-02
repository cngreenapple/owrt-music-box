#!/bin/bash
echo "=== ST4 PLAYER INSTALLER ==="

# 1. Update System & Install Core Apps
echo "[1/4] Installing System Dependencies (MPV, Node.js, Python)..."
sudo apt update
sudo apt install -y python3-pip python3-venv mpv ffmpeg curl git

# Install Node.js (Versi 18.x LTS)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# 2. Install yt-dlp Terbaru (Langsung Binary biar update)
echo "[2/4] Installing Latest yt-dlp..."
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

# 3. Install Python Libraries
echo "[3/4] Installing Python Requirements..."
pip3 install flask ytmusicapi

# 4. Setup Permissions
echo "[4/4] Setting Permissions..."
chmod +x play.sh
chmod +x toggle_output.sh

echo "=== INSTALLATION COMPLETE! ==="
echo "Run with: python3 app.py"
