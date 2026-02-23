# 🎬 Jellyfin + Tailscale + Podman (Rootless)  
**One-click start/stop Jellyfin media server**  

A clean, toggleable, GPU-accelerated Jellyfin launcher for Linux desktops using **Podman (rootless)**.  
Perfect for desktop icons — click once to start, click again to stop.  
Works great with Tailscale for remote access from anywhere.

---

## ✨ Features

- **One-click toggle** — start or stop with a single click (ideal for `.desktop` shortcuts)  
- **Auto-updates** — always pulls the latest Jellyfin image on every launch  
- **Tailscale auto-detection** — automatically exposes the server on your Tailscale IP  
- **Full NVIDIA GPU passthrough** — hardware acceleration with CDI (modern rootless way)  
- **Pasta networking** — modern & fast (with Slirp fallback)  
- **Media safety check** — refuses to start if your media drive is not mounted  
- **Atomic lock** — prevents accidental double-starts  
- **Desktop notifications** + health check  
- **Weekly background cleanup** — removes dangling images & unused volumes  
- **No personal data** — fully customizable via environment variables or the top config section  

---

## 📋 Prerequisites

Before using the script, make sure you have:

1. **Podman** installed and running rootless  
   sudo dnf install podman   # Fedora / RHEL / Rocky
    or
   sudo apt install podman   # Ubuntu / Debian
   systemctl --user enable --now podman.socket

2. Tailscale (optional but recommended for remote access)
Installed and connected.

3. NVIDIA GPU (optional)  NVIDIA drivers installed  
nvidia-container-toolkit installed

4. A mounted media folder containing your movies/TV shows.

---

## 🚀 Installation (2 minutes)
 
 1. Download the script

mkdir -p ~/bin
curl -L -o ~/bin/jellyfin.sh \
  https://raw.githubusercontent.com/YOUR-GITHUB-USERNAME/jellyfin-podman-tailscale/main/jellyfin.sh
chmod +x ~/bin/jellyfin.sh

(Replace the URL with your actual repo link after you push)

2. Configure the media pathOpen the script and change only this line:

MEDIA_PATH="/CHANGE/THIS/TO/YOUR/MEDIA/PATH"

Examples:

MEDIA_PATH="/run/media/$(whoami)/Movies"
MEDIA_PATH="/mnt/media"
MEDIA_PATH="/home/$(whoami)/Media"

You can also set it with an environment variable (no editing needed):

export JELLYFIN_MEDIA_PATH="/run/media/$(whoami)/Movies"
~/bin/jellyfin.sh

3. (Optional) Create a desktop launcherCopy the .desktop file I provided earlier to:

~/.local/share/applications/Jellyfin.desktop

Then run:

chmod +x ~/.local/share/applications/Jellyfin.desktop
update-desktop-database ~/.local/share/applications/

Now search “Jellyfin” in your menu or drag the icon to your desktop.

---

## 🛠️ Customization (All options)
 
 All settings can be changed in the USER CONFIGURATION section at the top of the script, or overridden with environment variables:

Variable                 Default           Description

JELLYFIN_MEDIA_PATH  /  (required)     /     Path to your movies/TV folder
 
JELLYFIN_NET_MODE    /    pasta       /      pasta or slirp

JELLYFIN_HOST_USER  /  current user    /     Rarely needed

JELLYFIN_IMAGE   /  docker.io/jellyfin/... / Custom image (e.g. beta)

JELLYFIN_CONTAINER_NAME / jellyfin    /      Change if you want multiple instances

JELLYFIN_PORT      /       8096       /      Web UI port

JELLYFIN_MEMORY     /      12g        /      Memory limit

JELLYFIN_SHM_SIZE     /    8g        /       Shared memory for transcoding

JELLYFIN_CPUS       /      6         /       CPU cores


xample (in terminal or ~/.bashrc):

export JELLYFIN_MEDIA_PATH="/mnt/bigdrive/Media"
export JELLYFIN_NET_MODE="slirp"
export JELLYFIN_MEMORY="16g"

---

## 🖥️  How to UseDouble-click the desktop icon → starts Jellyfin (if stopped)  
Click again → stops Jellyfin cleanly  
First run will take ~30 seconds (pulls image + GPU setup)  
After start, you’ll see a notification with local + Tailscale URLs

Access Jellyfin at:  Local: http://localhost:8096  
Tailscale: http://100.x.x.x:8096 (shown in notification)

---

## 🔧 Troubleshooting"Media folder not found!"
→ Double-check MEDIA_PATH and that the drive is mounted."Process already active…"
→ Wait a few seconds or run podman stop jellyfin manually.No Tailscale URL in notification
→ Make sure Tailscale is running (tailscale status).GPU not detected
→ Run nvidia-smi and nvidia-ctk --version.Container won't start
→ Check logs: podman logs jellyfin

---

## 📝 License & CreditsFree to use, modify, and share  
Original concept & core script by Rathgesh  
Cleaned, documented, and generalized for the community by Grok

Made with ❤️ for the self-hosted community.

---

## ⭐ Star this repo if it helps you!
 
 Any feedback or improvements? Open an issue or PR — happy to help!






