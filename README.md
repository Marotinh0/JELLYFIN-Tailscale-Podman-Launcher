# 🎬 Jellyfin + Tailscale + Podman (Rootless)

**One-click start/stop Jellyfin media server**

A clean, toggleable, GPU-accelerated Jellyfin launcher for Linux desktops using **Podman (rootless)**. Perfect for desktop icons — click once to start, click again to stop. Works great with Tailscale for remote access from anywhere.

---

## ✨ Features

- **One-click toggle** — start or stop with a single click (ideal for `.desktop` shortcuts)
- **Auto-updates** — pulls the latest Jellyfin image on every launch (optional, can be disabled)
- **Tailscale auto-detection** — automatically exposes the server on your Tailscale IP
- **Full NVIDIA GPU passthrough** — hardware acceleration with CDI (modern rootless way), with automatic corruption detection
- **Pasta networking** — modern & fast (with Slirp fallback)
- **Media safety check** — refuses to start if your media drive is not mounted
- **Atomic lock** — prevents accidental double-starts
- **Real health check** — polls Jellyfin until it actually responds, instead of guessing with a fixed wait
- **Startup validation** — checks your port/memory/CPU settings before launching, with clear error messages
- **Centralized logging** — every run is recorded to a local log file and to `journald`
- **Desktop notifications** for start, stop, and failure states
- **Weekly background cleanup** — removes dangling images & unused volumes
- **No personal data** — fully customizable via environment variables or the top config section

---

## 📋 Prerequisites

Before using the script, make sure you have the following.

### 1. Podman & networking tools

```bash
# Arch Linux / CachyOS
sudo pacman -S podman passt libnotify wget

# Fedora
sudo dnf install podman passt libnotify wget

# Ubuntu / Debian
sudo apt install podman passt libnotify-bin wget
```

Then enable the rootless user socket (**required**):

```bash
systemctl --user enable --now podman.socket
```

### 2. Tailscale (optional, recommended for remote access)

Install Tailscale and make sure you're logged in and connected:

```bash
tailscale status
```

If this command works and shows your device, you're good. If you skip Tailscale, the script will simply expose Jellyfin on `localhost` only.

### 3. NVIDIA GPU (optional, for hardware transcoding)

- NVIDIA drivers installed and working — confirm with `nvidia-smi`
- `nvidia-container-toolkit` installed
- The CDI configuration generated at least once (the script will also auto-generate/refresh this for you):

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

If you don't have an NVIDIA GPU, you can ignore this section entirely — Jellyfin will run fine using software (CPU) transcoding.

### 4. A media folder

A mounted drive or folder containing your movies/TV shows, with a path you know (e.g. `/mnt/media`, `/run/media/yourname/Movies`).

---

## 🚀 Installation (2 minutes)

### Step 1 — Download the script

```bash
# Create a bin folder for your personal scripts
mkdir -p ~/bin

# Download the script
curl -L -o ~/bin/jellyfin.sh \
  https://raw.githubusercontent.com/Marotinh0/JELLYFIN-Tailscale-Podman-Launcher/main/jellyfin.sh

# Make it executable
chmod +x ~/bin/jellyfin.sh
```

### Step 2 — Set your media path

This is the **only thing you must change** before running the script. You have two options — pick whichever is more comfortable:

**Option A — Edit the script directly.** Open `~/bin/jellyfin.sh` in a text editor, find this line near the top:

```bash
MEDIA_PATH="${JELLYFIN_MEDIA_PATH:-/CHANGE/THIS/TO/YOUR/MEDIA/PATH}"
```

and replace the path with your real media folder, for example:

```bash
MEDIA_PATH="${JELLYFIN_MEDIA_PATH:-/mnt/media}"
```

**Option B — Use an environment variable** (no editing required):

```bash
export JELLYFIN_MEDIA_PATH="/run/media/$(whoami)/Movies"
~/bin/jellyfin.sh
```

Common examples of valid paths:

```bash
MEDIA_PATH="/run/media/$(whoami)/Movies"
MEDIA_PATH="/mnt/media"
MEDIA_PATH="/home/$(whoami)/Media"
```

### Step 3 — Run it

```bash
~/bin/jellyfin.sh
```

The first run will take longer (~30 seconds) since it pulls the image and sets up the GPU. You'll get a desktop notification once Jellyfin is up, showing the local URL (and the Tailscale URL, if available).

### Step 4 — (Optional) Create a desktop launcher

Create a file at `~/.local/share/applications/Jellyfin.desktop` with contents similar to:

```ini
[Desktop Entry]
Type=Application
Name=Jellyfin
Comment=Start/stop the Jellyfin media server
Exec=/home/yourname/bin/jellyfin.sh
Icon=jellyfin
Terminal=false
Categories=AudioVideo;Video;
```

Then register it:

```bash
chmod +x ~/.local/share/applications/Jellyfin.desktop
update-desktop-database ~/.local/share/applications/
```

Now search "Jellyfin" in your application menu, or drag the icon to your desktop/taskbar. Clicking it toggles the server on and off.

---

## 🛠️ Customization (all options)

All settings live in the **USER CONFIGURATION** section at the top of the script, and every one of them can also be overridden with an environment variable — handy if you want to keep the script itself untouched and generic.

| Variable                    | Default                          | Description                                                            |
|:-----------------------------|:---------------------------------:|--------------------------------------------------------------------------|
| `JELLYFIN_MEDIA_PATH`         | *(required — placeholder by default)* | Path to your movies and TV shows folder                                |
| `JELLYFIN_NET_MODE`           | `pasta`                          | Network mode: `pasta` (recommended, fast) or `slirp` (more compatible) |
| `JELLYFIN_HOST_USER`          | current user                     | Rarely needed — auto-detected from your login                          |
| `JELLYFIN_IMAGE`              | `docker.io/jellyfin/jellyfin:latest` | Custom image, e.g. a beta or pinned version tag                    |
| `JELLYFIN_CONTAINER_NAME`     | `jellyfin`                       | Container name — change this if you want multiple instances            |
| `JELLYFIN_PORT`               | `8096`                           | Web UI port (must be between 1024–65535)                               |
| `JELLYFIN_MEMORY`             | `12g`                            | Memory limit for the container (e.g. `12g`, `512m`)                    |
| `JELLYFIN_SHM_SIZE`           | `8g`                             | Shared memory size, used for hardware transcoding                      |
| `JELLYFIN_CPUS`               | `6`                              | Maximum CPU cores allowed (decimals allowed, e.g. `6.5`)                |
| `JELLYFIN_PIDS_LIMIT`         | `4096`                           | Maximum number of processes inside the container (safety limit)       |
| `JELLYFIN_AUTO_PULL`          | `true`                           | Auto-update the Jellyfin image on every launch: `true` or `false`      |
| `JELLYFIN_HEALTH_TIMEOUT`     | `30`                             | Max seconds to wait for Jellyfin to respond before falling back to a looser "is it still running?" check |

Example — setting several at once, either directly in your terminal or in `~/.bashrc` / `~/.zshrc` to make them permanent:

```bash
export JELLYFIN_MEDIA_PATH="/mnt/bigdrive/Media"
export JELLYFIN_NET_MODE="slirp"
export JELLYFIN_MEMORY="16g"
export JELLYFIN_AUTO_PULL="false"
```

---

## 🖥️ How to Use

- **Double-click the desktop icon (or run the script)** → starts Jellyfin if it's currently stopped
- **Click again (or run the script again)** → stops Jellyfin cleanly
- The first run takes ~30 seconds (pulls the image + sets up the GPU); later runs are much faster
- Once it's up, you'll get a notification with the URLs to access it

Access Jellyfin at:

- **Local:** `http://localhost:8096`
- **Tailscale:** `http://100.x.x.x:8096` (your actual Tailscale IP is shown in the notification)

### Checking logs

Every run writes a timestamped log, useful if the notification disappears before you read it:

```bash
# Tail the live log file
tail -f "$XDG_RUNTIME_DIR/jellyfin.log"

# Or search recent history in journald
journalctl -t jellyfin-start --since "1 hour ago"

# Container's own logs (Jellyfin app output)
podman logs jellyfin
```

---

## 🔧 Troubleshooting

**"Missing dependencies: ..."**
→ One or more required commands (`podman`, `notify-send`, `mountpoint`) aren't installed. Revisit the [Prerequisites](#-prerequisites) section and install what's missing.

**"Invalid port / memory / CPU"**
→ One of your `JELLYFIN_PORT`, `JELLYFIN_MEMORY`, or `JELLYFIN_CPUS` values doesn't match the expected format (see the [Customization table](#-customization-all-options) above for valid examples). Fix the value and try again.

**"Media folder not found!"**
→ Double-check `MEDIA_PATH` (or `JELLYFIN_MEDIA_PATH`) and make sure the drive is actually mounted and accessible.

**"Already starting… (wait a moment)"**
→ The script is already mid-launch from a previous click. Wait a few seconds, or if it seems stuck, run `podman stop jellyfin` manually and try again.

**No Tailscale URL in the notification**
→ Make sure Tailscale is installed, running, and connected: `tailscale status`. If it's not running, Jellyfin still works fine locally — you just won't get a remote URL.

**GPU not detected / no hardware transcoding**
→ Run `nvidia-smi` to confirm the driver is working, and `nvidia-ctk --version` to confirm the toolkit is installed. Check the script's log for `CDI` related warnings — see [Checking logs](#checking-logs) above.

**Container won't start / fails immediately**
→ Check the detailed logs: `podman logs jellyfin`, and the script's own log (see [Checking logs](#checking-logs)). The desktop failure notification also shows the last lines of the container's error output.

**Jellyfin image fails to update**
→ This is non-fatal — the script logs a warning and keeps using your existing local image. Check your internet connection, or set `JELLYFIN_AUTO_PULL=false` if you'd rather manage updates manually.

---

## 📝 License & Credits

Free to use, modify, and share. Original concept & core script by **Me**.

---

## ⭐ Star this repo if it helps you!

Any feedback or improvements? Open an issue or PR — happy to help!
