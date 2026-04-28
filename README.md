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

1. **Podman & Networking** installed and running rootless

   #Arch Linux / CachyOS
   sudo pacman -S podman passt libnotify wget
   
   #Fedora
   sudo dnf install podman passt
   
   #Ubuntu / Debian
   sudo apt install podman passt
   
   #Enable the user socket (Required):
    ```bash
   systemctl --user enable --now podman.socket
    ```

3. Tailscale (optional but recommended for remote access)
Installed and connected.

4. NVIDIA GPU (optional)  NVIDIA drivers installed  
NVIDIA Drivers installed and working (nvidia-smi).

nvidia-container-toolkit installed.

Generate the CDI configuration (Required for rootless GPU):
 ```bash
 sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```


4. A mounted media folder containing your movies/TV shows.

---

## 🚀 Installation (2 minutes)

 ```bash
 # Create bin folder
mkdir -p ~/bin

# Download the script
curl -L -o ~/bin/jellyfin.sh \
  https://raw.githubusercontent.com/Marotinh0/jellyfin-podman-tailscale/main/jellyfin.sh

# Make it executable
chmod +x ~/bin/jellyfin.sh
```
2. Configure the media pathOpen the script and change only this line:
```bash
MEDIA_PATH="/CHANGE/THIS/TO/YOUR/MEDIA/PATH"
```
Examples:
```bash
MEDIA_PATH="/run/media/$(whoami)/Movies"
MEDIA_PATH="/mnt/media"
MEDIA_PATH="/home/$(whoami)/Media"
```
You can also set it with an environment variable (no editing needed):
```bash
export JELLYFIN_MEDIA_PATH="/run/media/$(whoami)/Movies"
~/bin/jellyfin.sh
```
3. (Optional) Create a desktop launcherCopy the .desktop file I provided earlier to:
```bash
~/.local/share/applications/Jellyfin.desktop
```
Then run:
```bash
chmod +x ~/.local/share/applications/Jellyfin.desktop
update-desktop-database ~/.local/share/applications/
```
Now search “Jellyfin” in your menu or drag the icon to your desktop.

---

## 🛠️ Customization (All options)

All settings can be changed in the **USER CONFIGURATION** section at the top of the script, or overridden with environment variables:

| Variable                  | Default              | Description                                              |
|:--------------------------|:--------------------:|----------------------------------------------------------|
| `JELLYFIN_MEDIA_PATH`     | (required)           | Path to your movies and TV shows folder                  |
| `JELLYFIN_NET_MODE`       | `pasta`              | Network mode (`pasta` recommended or `slirp`)            |
| `JELLYFIN_HOST_USER`      | current user         | Rarely needed                                            |
| `JELLYFIN_IMAGE`          | official jellyfin    | Custom image (e.g. beta version)                         |
| `JELLYFIN_CONTAINER_NAME` | `jellyfin`           | Container name (for multiple instances)                  |
| `JELLYFIN_PORT`           | `8096`               | Web UI port                                              |
| `JELLYFIN_MEMORY`         | `12g`                | Memory limit for the container                           |
| `JELLYFIN_SHM_SIZE`       | `8g`                 | Shared memory for transcoding                            |
| `JELLYFIN_CPUS`           | `6`                  | Maximum CPU cores allowed                                |


Example (in terminal or ~/.bashrc):
```bash
export JELLYFIN_MEDIA_PATH="/mnt/bigdrive/Media"
export JELLYFIN_NET_MODE="slirp"
export JELLYFIN_MEMORY="16g"
```
---

## 🖥️  How to UseDouble-click the desktop icon → starts Jellyfin (if stopped)  
Click again → stops Jellyfin cleanly  
First run will take ~30 seconds (pulls image + GPU setup)  
After start, you’ll see a notification with local + Tailscale URLs

Access Jellyfin at:  Local: http://<!---->localhost:8096  
Tailscale: http://<!---->100.x.x.x:8096 (shown in notification)

---

## 🔧 Troubleshooting"Media folder not found!"
→ Double-check MEDIA_PATH and that the drive is mounted."Process already active…"
→ Wait a few seconds or run podman stop jellyfin manually.No Tailscale URL in notification
→ Make sure Tailscale is running (tailscale status).GPU not detected
→ Run nvidia-smi and nvidia-ctk --version.Container won't start
→ Check logs: podman logs jellyfin

---

## 📝 License & CreditsFree to use, modify, and share  
Original concept & core script by Me 

---

## ⭐ Star this repo if it helps you!
 
 Any feedback or improvements? Open an issue or PR — happy to help!






