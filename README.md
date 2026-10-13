# 🎬 Jellyfin + Tailscale + Podman Launcher

One-file, **rootless** Podman launcher for [Jellyfin](https://jellyfin.org) with **GPU transcoding**, optional **Tailscale** remote access, **safe automatic updates** and a **click-to-toggle desktop icon**.

Pick the script that matches your graphics card:

| Script | GPU | How the GPU is passed to the container |
|---|---|---|
| [`jellyfin-nvidia.sh`](jellyfin-nvidia.sh) | NVIDIA (NVENC/NVDEC) | CDI (`--device nvidia.com/gpu=all`) |
| [`jellyfin-amd.sh`](jellyfin-amd.sh) | AMD (VA-API / Mesa). Also works for **Intel** iGPU/Arc VA-API (`JELLYFIN_GPU_VENDOR=intel`) | the `/dev/dri/renderD*` render node only |

Both scripts are generated from the same template, so they behave identically except for the GPU part.

> No GPU, or you don't care about hardware transcoding? Either script still works: it logs a warning and Jellyfin falls back to CPU transcoding.

---

## ✨ Features

- **Toggle with one click** – start the server; click again to stop it cleanly.
- **Tailscale auto-detection** – if Tailscale is connected, Jellyfin is also published on your Tailscale IP, so you can watch from anywhere with no port forwarding and no public exposure.
- **Safe updates** – pulls the newest image and, *before* running a new version, **backs up your Jellyfin config/database** (a major upgrade can migrate the database in a way that can't be undone).
- **Media-drive guard** – refuses to start if your drive is unplugged or the folder is empty, so Jellyfin never "forgets" your library.
- **Hardened container** – see [Security model](#-security-model).
- **Real health check** – polls Jellyfin instead of a blind `sleep`, with a longer wait after an update (database migration).
- **GPU fallback** – if the GPU setup is broken the script retries *without* the GPU (software transcoding) instead of leaving you with no server (unless you set `JELLYFIN_REQUIRE_GPU=true`).
- **Extra commands** – `status`, `logs`, `update`, `backup`, `restore`, `--dry-run`.
- **Everything configurable with environment variables** – no need to edit the script.
- Log file with rotation + `journald` + desktop notifications.

---

## 📦 Requirements

| What | Why | Required? |
|---|---|---|
| Linux with **systemd** and a normal user session | provides `$XDG_RUNTIME_DIR` | yes |
| **Podman ≥ 4.8** (5.x recommended) | runs the container rootless | yes |
| **passt** (provides `pasta`) | fast rootless networking | yes (or use `JELLYFIN_NET_MODE=slirp` + `slirp4netns`) |
| **crun** | the `--group-add keep-groups` option (GPU access) only works with crun | yes for GPU |
| `curl` (or `wget`) | health checks | recommended |
| `libnotify` (`notify-send`) | desktop notifications | optional |
| `zstd` | smaller backups (falls back to gzip) | optional |
| **Tailscale** | remote access | optional |
| NVIDIA only: proprietary driver + **nvidia-container-toolkit** | GPU passthrough | NVIDIA script |
| AMD/Intel only: Mesa VA-API drivers (usually already installed) and membership in the `render` group | GPU access | AMD script |

Install examples (package names can vary a little between releases):

```bash
# Arch / CachyOS / Manjaro
sudo pacman -S podman passt crun curl libnotify zstd tailscale
#   NVIDIA also:  sudo pacman -S nvidia-container-toolkit

# Fedora
sudo dnf install podman passt crun curl libnotify zstd
#   NVIDIA also: install nvidia-container-toolkit from NVIDIA's repository
#   (https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

# Debian / Ubuntu
sudo apt install podman passt crun curl libnotify-bin zstd
```

---

## 🚀 Quick start

```bash
# 1. Download the script for your GPU into ~/bin and make it executable
mkdir -p ~/bin
curl -fsSL -o ~/bin/jellyfin-amd.sh \
  https://raw.githubusercontent.com/Marotinh0/JELLYFIN-Tailscale-Podman-Launcher/main/jellyfin-amd.sh     # or jellyfin-nvidia.sh
chmod +x ~/bin/jellyfin-amd.sh

# 2. Tell it where your media is (or edit MEDIA_PATH inside the script)
export JELLYFIN_MEDIA_PATH="/mnt/media"

# 3. Look at what it WOULD do (changes nothing)
~/bin/jellyfin-amd.sh --dry-run

# 4. Run it – the first start downloads the image and takes a minute
~/bin/jellyfin-amd.sh
```

Then open **http://localhost:8096** and finish the Jellyfin setup wizard.

> 💡 To make `JELLYFIN_MEDIA_PATH` permanent, either edit the `MEDIA_PATH=` line near the top of the script, or `export` the variable in `~/.bashrc` / `~/.config/environment.d/jellyfin.conf`.

### First-time Jellyfin setup (important!)

1. **Add libraries** by browsing to **`/media`** (your `MEDIA_PATH`, read-only) – and **`/media2`** if you set `JELLYFIN_MEDIA_PATH_2`.
2. **Turn on hardware transcoding:** *Dashboard → Playback → Transcoding*
   - **NVIDIA:** Hardware acceleration = **Nvidia NVENC**, then tick the codecs your card can decode.
   - **AMD / Intel:** Hardware acceleration = **Video Acceleration API (VAAPI)**, VA-API device = the path the script prints in its log (for example `/dev/dri/renderD128`).
3. **Set the transcode path** (so the RAM/disk scratch space is actually used): *Dashboard → Playback → Transcoding → "Transcode path"* = **`/config/transcodes`**.
4. Test it: play a video that needs transcoding and check *Dashboard → Activity*, or run `nvidia-smi` / `radeontop` while it plays.

### Desktop icon

Copy the matching `.desktop` file from this repo to `~/.local/share/applications/`, edit the `Exec=` line to the **absolute path** of your script, and you get an app-menu entry that toggles Jellyfin (plus right-click actions *Show status* and *Update Jellyfin now*).

---

## 🎮 GPU setup

### NVIDIA

1. Install the proprietary NVIDIA driver and **nvidia-container-toolkit**.
2. Generate the **CDI spec** once (it tells Podman which driver libraries and device nodes to inject):
   ```bash
   sudo mkdir -p /etc/cdi
   sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
   nvidia-ctk cdi list        # should list nvidia.com/gpu=all, =0, ...
   ```
3. **Regenerate it after every driver update.** Recent toolkit versions ship a `nvidia-cdi-refresh` systemd unit that does this automatically (check with `systemctl status nvidia-cdi-refresh.path`). If yours doesn't, either repeat the command above or let the script do it (next section).

The script checks that the CDI spec exists, that it mentions your *current* driver version, and that the requested device exists – and tells you the exact fix command if something is off.

**Optional: auto-regenerate the CDI spec.** Set `JELLYFIN_CDI_AUTOREGEN=true` and allow *only that one command* without a password:

```bash
sudo visudo -f /etc/sudoers.d/jellyfin-cdi
# paste (replace YOUR_USER):
YOUR_USER ALL=(root) NOPASSWD: /usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Multi-GPU? Use `JELLYFIN_NVIDIA_DEVICE="nvidia.com/gpu=0"` (or `=1`, …).

### AMD (and Intel)

1. Make sure Mesa VA-API drivers are installed (`vainfo` should list `VAProfileH264…` etc.).
2. Put your user in the `render` (and `video`) group, then **log out and back in**:
   ```bash
   sudo usermod -aG render,video "$USER"
   ```
3. That's it – the script finds `/dev/dri/renderD*` and passes **only that device**.

Two GPUs (for example the Ryzen iGPU plus a dedicated card)? The script picks the first node whose PCI vendor matches `JELLYFIN_GPU_VENDOR` (`amd` by default; `intel` or `any` also accepted), or force one with `JELLYFIN_RENDER_NODE=/dev/dri/renderD129`.

---

## ⚙️ Configuration

Every setting can be changed in the `USER CONFIGURATION` section of the script **or** with an environment variable, e.g. `JELLYFIN_MEMORY=12g ./jellyfin-amd.sh`.

| Variable | Default | Meaning |
|---|---|---|
| `JELLYFIN_MEDIA_PATH` | *(must be set)* | Your media folder → `/media` (read-only) |
| `JELLYFIN_MEDIA_PATH_2` | *(empty)* | Optional 2nd folder → `/media2` (read-only; skipped with a warning if unplugged) |
| `JELLYFIN_IMAGE` | `docker.io/jellyfin/jellyfin:latest` | Pin a version (`…:10.11.0`) or digest for full control |
| `JELLYFIN_AUTO_PULL` | `true` | Pull the newest image at every start |
| `JELLYFIN_PORT` | `8096` | Port **on this machine** |
| `JELLYFIN_LAN_ACCESS` | `true` | Also listen on your LAN IP (`false` = localhost + Tailscale only) |
| `JELLYFIN_DISCOVERY` | `false` | Publish UDP 7359 (client auto-discovery; often ineffective, see script) |
| `JELLYFIN_NET_MODE` | `pasta` | `pasta` or `slirp` |
| `JELLYFIN_ALLOW_HOST_ACCESS` | `false` | Let the container reach services on this machine's loopback |
| `JELLYFIN_LAN_SUBNET` | *(empty)* | e.g. `192.168.1.` – warns if your LAN IP is outside it |
| `JELLYFIN_MEMORY` | `8g` | Container RAM limit (no swap) |
| `JELLYFIN_SHM_SIZE` | `2g` | `/dev/shm` size |
| `JELLYFIN_TMP_SIZE` | `1g` | `/tmp` (RAM) size |
| `JELLYFIN_CPUS` | `auto` | CPU cores cap (`auto` = half of your logical CPUs, min 2) |
| `JELLYFIN_CPU_SHARES` | `512` | Relative CPU priority (1024 = normal). Lower = your desktop/games win |
| `JELLYFIN_PIDS_LIMIT` | `4096` | Max processes in the container |
| `JELLYFIN_TRANSCODE_MODE` | `ram` | `ram` (tmpfs) or `disk` (Podman volume) |
| `JELLYFIN_TRANSCODE_SIZE` | `4g` | tmpfs size when in `ram` mode |
| `JELLYFIN_TRANSCODE_PATH` | `/config/transcodes` | Path inside the container (set the same in the Jellyfin dashboard) |
| `JELLYFIN_READ_ONLY` | `false` | Read-only root filesystem (extra hardening) |
| `JELLYFIN_REQUIRE_GPU` | `false` | `true` = refuse to start without a working GPU |
| `JELLYFIN_BACKUP_BEFORE_UPDATE` | `true` | Back up the config before running a *new* image |
| `JELLYFIN_BACKUP_KEEP` | `3` | How many backups to keep |
| `JELLYFIN_BACKUP_DIR` | `~/.local/share/jellyfin-backups` | Where backups go |
| `JELLYFIN_HEALTH_TIMEOUT` | `45` | Seconds to wait for Jellyfin on a normal start |
| `JELLYFIN_HEALTH_TIMEOUT_UPDATE` | `180` | …after an image update (DB migration) |
| `JELLYFIN_STOP_TIMEOUT` | `20` | Seconds Jellyfin gets to shut down before being killed |
| `JELLYFIN_TZ` | *(auto)* | Timezone, e.g. `Europe/Berlin` |
| `JELLYFIN_CONTAINER_NAME` | `jellyfin` | Only change for multiple instances |
| **NVIDIA only** | | |
| `JELLYFIN_NVIDIA_DEVICE` | `nvidia.com/gpu=all` | CDI device name |
| `JELLYFIN_CDI_DIRS` | `/etc/cdi /var/run/cdi` | Where CDI specs live |
| `JELLYFIN_CDI_AUTOREGEN` | `false` | Auto-run `sudo -n nvidia-ctk cdi generate` when the spec is missing/outdated |
| **AMD / Intel only** | | |
| `JELLYFIN_GPU_VENDOR` | `amd` | `amd`, `intel` or `any` |
| `JELLYFIN_RENDER_NODE` | *(auto)* | Force a node, e.g. `/dev/dri/renderD129` |

> **Sizing tip:** the RAM-backed folders (`/tmp`, the transcode tmpfs and `/dev/shm`) count against `JELLYFIN_MEMORY`. The script warns you if `SHM + TMP + TRANSCODE` is bigger than the limit. Short on RAM? Use `JELLYFIN_TRANSCODE_MODE=disk`.

---

## 🧰 Commands

```text
jellyfin-*.sh [COMMAND] [--dry-run]

  toggle   (default) start if stopped, stop if running
  start    start (does nothing if already running)
  stop     stop cleanly
  restart  stop + start
  update   pull the newest image (with a config backup) and restart
  status   state, health, uptime and URLs        (exit code 3 when stopped)
  logs     follow the container logs
  backup   export the config volume (Jellyfin must be stopped)
  restore FILE   replace the config with a backup (asks for confirmation)
  help | --version

  --dry-run   print the exact `podman run` command, change nothing
```

Where things live:

| What | Where |
|---|---|
| Script log | `~/.local/state/jellyfin-start/jellyfin.log` (rotated) · `journalctl --user -t jellyfin-start` |
| Container log | `jellyfin-*.sh logs` or `podman logs jellyfin` |
| Backups | `~/.local/share/jellyfin-backups/` (mode `600`, newest 3 kept) |
| Config / cache | Podman volumes `jellyfin_config` and `jellyfin_cache` (survive deleting the container) |

---

## 🌐 Tailscale (remote access)

1. [Install Tailscale](https://tailscale.com/download) on the server and on your phone/laptop, and sign in to the same tailnet: `sudo tailscale up`.
2. Start Jellyfin with the script. If Tailscale is connected you'll see `🌐 Tailscale: http://100.x.y.z:8096` in the notification and in `status`.
3. In the Jellyfin app on any device in your tailnet, connect to that address.

Good to know:

- The IP is detected **when Jellyfin starts**. If you connect Tailscale *after* starting Jellyfin, run `jellyfin-*.sh restart`.
- Traffic inside a tailnet is already end-to-end encrypted (WireGuard), so plain `http://` is fine there. For HTTPS with a real certificate, look at [`tailscale serve`](https://tailscale.com/kb/1312/serve) (not configured by this script).
- The port is published only on `127.0.0.1`, your LAN IP and your Tailscale IP – **never on `0.0.0.0`** – and nothing is exposed to the public internet.

### Firewall example (ufw)

```bash
# LAN clients (adjust the subnet)
sudo ufw allow from 192.168.1.0/24 to any port 8096 proto tcp
# Tailscale clients
sudo ufw allow in on tailscale0 to any port 8096 proto tcp
```

---

## 🔄 Updates, backups & restore

- At every start (with `JELLYFIN_AUTO_PULL=true`) the script pulls the image. **If it is a new image**, it first exports the config volume to `~/.local/share/jellyfin-backups/`. **If that backup fails, the start is aborted** – your data matters more than the update.
- After an update, check *Dashboard → Playback → Transcoding* – hardware-acceleration settings are occasionally reset by big upgrades.
- Want full control? Pin a version and disable pulling:
  `JELLYFIN_IMAGE=docker.io/jellyfin/jellyfin:10.11.0 JELLYFIN_AUTO_PULL=false`
- Manual backup: `jellyfin-*.sh stop && jellyfin-*.sh backup`

**Restore** (for example after a bad update or a broken database):

```bash
jellyfin-*.sh stop
jellyfin-*.sh restore ~/.local/share/jellyfin-backups/jellyfin_config-20260101-120000.tar.zst
#   → asks you to type YES, makes a safety backup of the current config, then restores
# If the problem was a new Jellyfin version, pin the old one before starting again:
JELLYFIN_IMAGE=docker.io/jellyfin/jellyfin:10.10.7 JELLYFIN_AUTO_PULL=false jellyfin-*.sh start
```

---

## 🔒 Security model

What the script does so that a bug (or a malicious media file) in Jellyfin has as little power as possible:

| Measure | Effect |
|---|---|
| **Rootless Podman** (script refuses to run as root) | the container can't touch anything your user can't |
| `--user UID:GID` + `--userns keep-id` | Jellyfin runs as **you**, never as root, even inside the container |
| `--cap-drop=ALL` | no Linux capabilities at all |
| `--security-opt no-new-privileges` | setuid binaries can't escalate |
| Media mounted **`:ro`** | Jellyfin can't modify or delete your files |
| Only the **GPU device** is passed (NVIDIA: the CDI device; AMD: `renderD*` only, **not** `card*`) | no access to display/mode-setting nodes |
| `--memory` = `--memory-swap`, `--cpus`, `--pids-limit` | resource exhaustion and fork bombs are contained |
| Ports bound to **specific IPs** (localhost / LAN / Tailscale) | never `0.0.0.0` |
| `ALLOW_HOST_ACCESS=false` | the container can't connect to services on your machine's loopback |
| Optional `--read-only` rootfs | nothing in the image can be modified |
| SELinux label disabled **only** if SELinux is actually enforcing; the `:Z` relabel flag is **not** used | no accidental relabeling of your whole media drive |
| No Podman API socket started, `PATH` fixed, state files `600/700` | smaller attack surface on the host |
| Weekly cleanup removes **dangling images only** | never `podman volume prune` (which can delete other projects' volumes) |

Not covered (be realistic): Jellyfin itself is a large web application – keep it updated, use strong passwords, and don't forward port 8096 to the internet. Tailscale is the safer way to reach it remotely.

---

## 🩺 Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `MEDIA_PATH is not set` | Set `JELLYFIN_MEDIA_PATH` or edit the script |
| `Media folder not found or empty` | Drive not mounted/plugged in – by design the script won't start with an empty library |
| `Missing required dependencies: pasta` | Install `passt`, or use `JELLYFIN_NET_MODE=slirp` (needs `slirp4netns`) |
| `Port … already allocated` / bind error | Something else uses port 8096 → `JELLYFIN_PORT=8097` |
| **NVIDIA:** `unresolvable CDI devices` / `failed to stat CDI host device` | CDI spec missing or outdated → `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` (after every driver update). The script retries without GPU meanwhile |
| **NVIDIA:** `nvidia-smi` fails after a driver update | Reboot (kernel module and libraries are out of sync) |
| **AMD:** `No read/write permission on /dev/dri/renderD…` | `sudo usermod -aG render,video $USER`, then **log out and in** |
| GPU transcoding not used | Check *Dashboard → Playback*: right API selected, codecs ticked, correct device; watch the Jellyfin transcode log for ffmpeg errors |
| Warning about the `runc` runtime | `--group-add keep-groups` needs **crun**; install it and set it as Podman's default runtime |
| Library empty after update | Check your media is still mounted; check the log; restore a backup if needed |
| Tailscale URL missing | Tailscale wasn't connected at start → connect it and run `restart` |
| Desktop icon does nothing | Use the **absolute** path in `Exec=`; check `~/.local/state/jellyfin-start/jellyfin.log` |
| No notifications | Install `libnotify`; they need a graphical session (the script still works without them) |
| Transcodes fail with "no space left" | The RAM tmpfs is full → raise `JELLYFIN_TRANSCODE_SIZE` (and `JELLYFIN_MEMORY`) or use `JELLYFIN_TRANSCODE_MODE=disk` |
| Plugin can't reach Sonarr/Radarr on this PC | Use `JELLYFIN_ALLOW_HOST_ACCESS=true` (understand the trade-off above) or run them on the LAN IP |

When asking for help, include the output of `jellyfin-*.sh --dry-run` and the last lines of the log file.

---

## ⬆️ Upgrading from the old `jellyfin.sh`

- **Your library, users and settings are preserved** – the volume names (`jellyfin_config`, `jellyfin_cache`) and the `/media` mount point are unchanged. Stop the old container (`podman stop jellyfin`) before the first run of the new script.
- Renamed: `jellyfin.sh` → `jellyfin-nvidia.sh` (+ new `jellyfin-amd.sh`).
- Default limits are now smaller and consistent (8 GB RAM, 4 GB RAM transcode tmpfs, auto CPU cap). Raise them with the `JELLYFIN_*` variables if you have the RAM.
- `--cap-add` lines were removed (a non-root process doesn't use them), the `:Z` volume flags were removed, ports can no longer be bound to all interfaces, and the weekly `podman volume prune` was dropped (it could delete unrelated volumes).
- The script no longer starts `podman.socket` or generates the CDI file by itself; it tells you the command, or does it for you if you opt in with `JELLYFIN_CDI_AUTOREGEN=true`.
- New: `status`, `logs`, `update`, `backup`, `restore`, `--dry-run`, config backup before updates, GPU fallback, multi-GPU selection, optional second media folder, disk/RAM transcode choice.

---

## 🗑️ Uninstall

```bash
jellyfin-*.sh stop
podman rm -f jellyfin
podman volume rm jellyfin_config jellyfin_cache     # ⚠️ deletes your Jellyfin database & settings!
podman volume rm jellyfin_transcodes 2>/dev/null     # only exists in disk mode
rm -rf ~/.local/state/jellyfin-start                 # logs
# backups are in ~/.local/share/jellyfin-backups – delete them if you really want to
```

---

## 🤝 Contributing

Issues and pull requests are welcome. The two scripts are generated from a single template (`dev/jellyfin.tmpl.sh` + `dev/build.py`, run `python3 dev/build.py`); please change the template, not the generated files, and keep `shellcheck -S style` clean.

This project is not affiliated with Jellyfin, Podman, Tailscale, NVIDIA or AMD.
