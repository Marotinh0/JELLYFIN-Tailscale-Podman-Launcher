#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# 🎬 JELLYFIN + Tailscale + Podman (Rootless)
# ──────────────────────────────────────────────────────────────────────────────
# One-click start/stop Jellyfin with GPU acceleration, Tailscale remote access,
# automatic updates, desktop notifications, and media safety checks.
#
# ✨ Features
#   • Toggle via desktop icon (click to start / click to stop)
#   • Auto-updates Jellyfin on every launch (optional)
#   • Tailscale IP auto-detection for watching from anywhere
#   • Full NVIDIA GPU passthrough (CDI), with corruption detection
#   • Pasta networking (fast) with Slirp fallback
#   • Media drive safety check (prevents empty library)
#   • Atomic lock + real health check (polls Jellyfin instead of a fixed sleep)
#   • Startup config validation (port / memory / CPU) with clear error messages
#   • Centralized logging to a local file and to journald
#   • Weekly background cleanup
#   • Everything configurable with environment variables
#
# 📋 How to use
#   1. Save as ~/bin/jellyfin.sh (or anywhere in PATH)
#   2. chmod +x ~/bin/jellyfin.sh
#   3. Edit ONLY the USER CONFIGURATION section (or use env vars)
#   4. Create a desktop shortcut (see README)
#   5. Click the icon — done!
#
# ══════════════════════════════════════════════════════════════════════════════

# SAFETY SETTINGS
# set -e     → exit immediately if any command fails
# set -u     → treat unset variables as an error
# set -o pipefail → if any command in a pipe fails, the whole pipeline fails
# This makes the script very reliable and prevents silent errors.
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# 🛠️ USER CONFIGURATION — ONLY CHANGE THIS SECTION
# ══════════════════════════════════════════════════════════════════════════════

# NET_MODE
# Controls how the container talks to the outside world.
# "pasta" = modern, fast, recommended for most people
# "slirp" = older, more compatible fallback (use if you have network issues)
# You can also set it from terminal: export JELLYFIN_NET_MODE="pasta"
NET_MODE="${JELLYFIN_NET_MODE:-pasta}"

# HOST_USER
# Your Linux username. Used for file permissions and paths.
# Almost never needs changing — it auto-detects your current user.
# Override only if needed: export JELLYFIN_HOST_USER="yourname"
HOST_USER="${JELLYFIN_HOST_USER:-$(whoami)}"

# MEDIA_PATH ←←← THIS IS THE MOST IMPORTANT SETTING ←←←
# Full path to your movies/TV shows folder.
# The script will refuse to start if this folder is not mounted or missing.
# CHANGE THIS to your actual media location!
# Examples:
#   MEDIA_PATH="/run/media/$(whoami)/Movies"
#   MEDIA_PATH="/mnt/media"
#   MEDIA_PATH="/home/$(whoami)/Media"
# Override with env var: export JELLYFIN_MEDIA_PATH="/mnt/bigdrive/Media"
MEDIA_PATH="${JELLYFIN_MEDIA_PATH:-/CHANGE/THIS/TO/YOUR/MEDIA/PATH}"

# CONTAINER_IMAGE
# Which Jellyfin image to use. Default is the official latest stable.
# You can change to a beta or specific version if you want.
CONTAINER_IMAGE="${JELLYFIN_IMAGE:-docker.io/jellyfin/jellyfin:latest}"

# CONTAINER_NAME
# Name of the running container. Change only if you want multiple Jellyfin instances.
CONTAINER_NAME="${JELLYFIN_CONTAINER_NAME:-jellyfin}"

# JELLYFIN_PORT
# Web UI port (default 8096). Change only if port 8096 is already used on your PC.
JELLYFIN_PORT="${JELLYFIN_PORT:-8096}"

# Resource limits — change these if you want more or less power
# MEMORY_LIMIT: How much RAM Jellyfin can use (12g is safe for most PCs)
MEMORY_LIMIT="${JELLYFIN_MEMORY:-12g}"
# SHM_SIZE: Shared memory for hardware transcoding (important for GPU)
SHM_SIZE="${JELLYFIN_SHM_SIZE:-8g}"
# CPU_LIMIT: How many CPU cores Jellyfin can use
CPU_LIMIT="${JELLYFIN_CPUS:-6}"
# PIDS_LIMIT: Maximum number of processes (safety limit)
PIDS_LIMIT="${JELLYFIN_PIDS_LIMIT:-4096}"

# AUTO_PULL
# Automatically download the newest Jellyfin image on every launch: true or false.
# Set to "false" if you prefer to control updates manually (e.g. `podman pull`
# yourself), or if you're on a slow/metered connection.
AUTO_PULL="${JELLYFIN_AUTO_PULL:-true}"

# HEALTH_TIMEOUT
# Maximum time (in seconds) to wait for Jellyfin to respond after starting,
# before falling back to "is the process still alive?" as a looser success
# check. Increase this on slower machines or first-time startups.
HEALTH_TIMEOUT="${JELLYFIN_HEALTH_TIMEOUT:-30}"
# HEALTH_INTERVAL: time (in seconds) between each health check attempt.
HEALTH_INTERVAL=2

# ══════════════════════════════════════════════════════════════════════════════
# 🖥️ SYSTEM SETUP — No changes needed below
# ══════════════════════════════════════════════════════════════════════════════

# These environment variables make desktop notifications work and let Podman find its socket
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export HOME="/home/${HOST_USER}"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Icons used in desktop notifications
NOTIFY_ICON="jellyfin"
FAIL_ICON="error"

# Prepare runtime directory and Podman socket
# This makes sure Podman can run as your normal user (rootless mode)
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
[[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && \
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
systemctl --user start podman.socket --quiet || true

# LOCKFILE
# This folder acts as a "lock" so you can't accidentally start Jellyfin twice
LOCKFILE="$XDG_RUNTIME_DIR/${CONTAINER_NAME}-start.lock"

# LOGFILE
# Local log file with a history of everything the script did. Handy for
# debugging after the desktop notification has already disappeared.
# View it anytime with: tail -f "$XDG_RUNTIME_DIR/jellyfin.log"
LOGFILE="$XDG_RUNTIME_DIR/${CONTAINER_NAME}.log"

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

# log()
# Writes a timestamped, leveled (INFO/WARN/ERROR) message to LOGFILE and to
# journald (via "logger"). Check history later with:
#   journalctl -t jellyfin-start
log() {
    local level="$1"; shift
    local msg="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" | tee -a "$LOGFILE" || true
    logger -t "jellyfin-start" "[$level] $msg" || true
}

# notify()
# Thin wrapper around notify-send that never crashes the script — useful if
# you trigger this over SSH or from a cron job with no graphical session.
notify() {
    local title="$1" body="$2" icon="${3:-$NOTIFY_ICON}" expire="${4:-5000}"
    notify-send "$title" "$body" -i "$icon" --expire-time="$expire" 2>/dev/null || true
}

# check_deps()
# Confirms required commands exist before doing anything else, so a missing
# dependency fails fast with a clear message instead of mid-script.
check_deps() {
    local missing=()
    for cmd in podman notify-send mountpoint; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        log "ERROR" "Missing dependencies: ${missing[*]}"
        notify "Jellyfin ERROR" "Missing dependencies: ${missing[*]}" "$FAIL_ICON"
        exit 1
    fi
}

# validate_config()
# Sanity-checks the most sensitive settings (port / memory / CPU) so a typo
# in an env var is caught here, with a clear message, instead of producing a
# confusing failure deep inside `podman run`.
validate_config() {
    # Port must be numeric and in a sane, non-privileged range
    if ! [[ "$JELLYFIN_PORT" =~ ^[0-9]+$ ]] || \
       (( JELLYFIN_PORT < 1024 || JELLYFIN_PORT > 65535 )); then
        log "ERROR" "Invalid JELLYFIN_PORT: '$JELLYFIN_PORT' (use 1024-65535)"
        notify "Jellyfin ERROR" "Invalid port: $JELLYFIN_PORT" "$FAIL_ICON"
        exit 1
    fi

    # Memory must end in g, m, or k (e.g. 12g, 512m)
    if ! [[ "$MEMORY_LIMIT" =~ ^[0-9]+[gGmMkK]$ ]]; then
        log "ERROR" "Invalid MEMORY_LIMIT: '$MEMORY_LIMIT' (e.g. 12g)"
        notify "Jellyfin ERROR" "Invalid memory: $MEMORY_LIMIT" "$FAIL_ICON"
        exit 1
    fi

    # CPUs must be a positive number (decimals allowed, e.g. 6 or 6.5).
    # Uses awk instead of "bc" for the decimal check, since bc isn't
    # installed by default on every minimal distro — awk virtually always is.
    if ! [[ "$CPU_LIMIT" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
       ! awk -v n="$CPU_LIMIT" 'BEGIN { exit !(n > 0) }'; then
        log "ERROR" "Invalid CPU_LIMIT: '$CPU_LIMIT'"
        notify "Jellyfin ERROR" "Invalid CPU: $CPU_LIMIT" "$FAIL_ICON"
        exit 1
    fi
}

# wait_healthy()
# Replaces a fixed "sleep N" with real polling against Jellyfin's /health
# endpoint, checking every HEALTH_INTERVAL seconds up to HEALTH_TIMEOUT.
# If it times out but the container process is still running, that's treated
# as a (slow) success rather than a hard failure — first boots can be slow
# while Jellyfin sets up its internal database.
wait_healthy() {
    local elapsed=0
    log "INFO" "Waiting for Jellyfin to become healthy (timeout: ${HEALTH_TIMEOUT}s)..."
    while (( elapsed < HEALTH_TIMEOUT )); do
        if podman exec "${CONTAINER_NAME}" \
               wget -qO- "http://localhost:${JELLYFIN_PORT}/health" &>/dev/null; then
            log "INFO" "Jellyfin responded after ${elapsed}s"
            return 0
        fi
        sleep "$HEALTH_INTERVAL"
        (( elapsed += HEALTH_INTERVAL ))
    done
    log "WARN" "Jellyfin did not respond within ${HEALTH_TIMEOUT}s — checking if the process is still alive"
    podman ps --filter "name=^${CONTAINER_NAME}$" --filter status=running \
        --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔍 START CHECKS
# ══════════════════════════════════════════════════════════════════════════════

# Fail fast on missing tools or bad config, before touching podman/the system.
check_deps
validate_config

# Prevent running twice
if ! mkdir "$LOCKFILE" 2>/dev/null; then
    notify "Jellyfin" "Already starting… (wait a moment)" "$NOTIFY_ICON"
    exit 1
fi
# Remove the lock automatically even if the script crashes
trap 'rmdir "$LOCKFILE" 2>/dev/null || true' EXIT

log "INFO" "Script started by $HOST_USER (PID $$)"

# Toggle: Stop if already running
# This is what makes the desktop icon act as a start/stop switch
if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    log "INFO" "Running container detected — stopping it..."
    podman stop "${CONTAINER_NAME}" --time 15 >/dev/null
    log "INFO" "Container stopped successfully"
    notify "Jellyfin Stopped" "Server shut down cleanly" "$NOTIFY_ICON"
    exit 0
fi

# Clean up any old stopped container
podman rm -f "${CONTAINER_NAME}" 2>/dev/null || true

# Safety check — make sure your media drive is plugged in
# Prevents Jellyfin from starting with an empty library
if ! mountpoint -q "$MEDIA_PATH" && [[ ! -d "$MEDIA_PATH" ]]; then
    log "ERROR" "Media folder not found: $MEDIA_PATH"
    notify "Jellyfin ERROR" "Media folder not found!" "$FAIL_ICON"
    exit 1
fi

# Create persistent storage
# These volumes survive even if you delete the container
podman volume create jellyfin_config 2>/dev/null || true
podman volume create jellyfin_cache  2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════
# 📥 UPDATE & GPU PREP
# ══════════════════════════════════════════════════════════════════════════════

# Show a notification while we check for updates
notify "Jellyfin" "Checking for updates and preparing GPU..." "$NOTIFY_ICON" 2000

# Download the newest Jellyfin image, if AUTO_PULL is enabled.
# A failed pull (e.g. no internet) is logged but won't stop the script —
# it just keeps using whatever image is already cached locally.
if [[ "$AUTO_PULL" == "true" ]]; then
    log "INFO" "Checking for image update: $CONTAINER_IMAGE"
    if ! podman pull "$CONTAINER_IMAGE" -q >/dev/null 2>&1; then
        log "WARN" "Failed to update image — using existing local version"
    else
        log "INFO" "Image updated or already up to date"
    fi
fi

# Force-load NVIDIA modules to ensure /dev/nvidia-modeset exists.
# This prevents the "failed to stat CDI host device" error.
# Commented out by default since it requires sudo, and we don't want this
# script to demand elevated privileges out of the box. If you hit GPU
# detection issues, uncomment the line below — ideally after adding a
# narrowly-scoped NOPASSWD rule to /etc/sudoers.d for just these modprobe
# calls, rather than granting broad sudo access:
#   youruser ALL=(root) NOPASSWD: /usr/sbin/modprobe nvidia, \
#     /usr/sbin/modprobe nvidia-modeset, /usr/sbin/modprobe nvidia-uvm, \
#     /usr/sbin/modprobe nvidia-drm
#(remove) sudo modprobe -q nvidia nvidia-modeset nvidia-uvm nvidia-drm || true

# NVIDIA GPU setup (auto)
# Creates the CDI configuration file so Jellyfin can use your GPU.
# Regenerates it when it's missing, older than 1 day, OR when it exists but
# fails validation via "nvidia-ctk cdi list" (catches a corrupted file that
# a simple age check would otherwise accept as still valid).
if command -v nvidia-ctk &>/dev/null; then
    CDI_NEEDS_REGEN=false

    if [[ ! -f /etc/cdi/nvidia.yaml ]]; then
        CDI_NEEDS_REGEN=true
        log "INFO" "CDI missing — generating..."
    elif [[ -n "$(find /etc/cdi/nvidia.yaml -mtime +1 2>/dev/null)" ]]; then
        CDI_NEEDS_REGEN=true
        log "INFO" "CDI outdated — regenerating..."
    elif ! nvidia-ctk cdi list &>/dev/null; then
        CDI_NEEDS_REGEN=true
        log "WARN" "CDI invalid or corrupted — regenerating..."
    fi

    if [[ "$CDI_NEEDS_REGEN" == "true" ]]; then
        if nvidia-ctk cdi generate \
               --output=/etc/cdi/nvidia.yaml \
               --device-name-strategy=type-index >/dev/null 2>&1; then
            log "INFO" "CDI generated successfully"
            systemctl --user restart podman.socket --quiet || true
        else
            log "WARN" "Failed to generate CDI — GPU might not be available"
        fi
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# 🌐 NETWORKING (Tailscale auto-detected)
# ══════════════════════════════════════════════════════════════════════════════

# Get your Tailscale IP (empty if Tailscale is not running)
TS_IP=$(tailscale ip -4 2>/dev/null || echo "")

# Set network flags and message based on NET_MODE
if [[ "$NET_MODE" == "pasta" ]]; then
    NET_FLAGS="pasta:--map-gw"
    MSG_MODE="🍝 Pasta (Optimized)"
else
    NET_FLAGS="slirp4netns:allow_host_loopback=true,mtu=9000"
    MSG_MODE="🛡️ Slirp (Stable)"
fi

# Port mapping for local access
PORT_ARGS="-p 127.0.0.1:${JELLYFIN_PORT}:${JELLYFIN_PORT}"
MSG_URLS="🏠 Local: http://localhost:${JELLYFIN_PORT}"

# Add Tailscale port mapping if Tailscale is active
if [[ -n "$TS_IP" ]]; then
    PORT_ARGS+=" -p ${TS_IP}:${JELLYFIN_PORT}:${JELLYFIN_PORT}"
    MSG_URLS+="\n🌐 Tailscale: http://${TS_IP}:${JELLYFIN_PORT}"
    log "INFO" "Tailscale detected: $TS_IP"
else
    log "INFO" "Tailscale not available — local access only"
fi

# PUBLISHED_URL is resolved into its own variable (instead of being built
# inline inside `podman run`) so the final value is easy to inspect/log
# before it's used.
PUBLISHED_URL="http://${TS_IP:-localhost}:${JELLYFIN_PORT}"

# ══════════════════════════════════════════════════════════════════════════════
# 🚀 LAUNCH JELLYFIN
# ══════════════════════════════════════════════════════════════════════════════

log "INFO" "Starting container: $CONTAINER_NAME"
log "INFO" "Image: $CONTAINER_IMAGE | Port: $JELLYFIN_PORT | Network: $MSG_MODE"

# This big command starts the Jellyfin container with all your settings
podman run -d \
    --name "${CONTAINER_NAME}" \
    --userns keep-id --user "$(id -u):$(id -g)" --group-add keep-groups \
    --device nvidia.com/gpu=all --security-opt label=disable \
    --security-opt no-new-privileges:true --cap-drop=ALL \
    --cap-add=CHOWN,FOWNER,DAC_OVERRIDE,NET_BIND_SERVICE,SYS_NICE \
    --memory "${MEMORY_LIMIT}" --shm-size="${SHM_SIZE}" \
    --cpus "${CPU_LIMIT}" --pids-limit "${PIDS_LIMIT}" \
    --network "${NET_FLAGS}" ${PORT_ARGS} \
    --restart on-failure --stop-timeout 20 \
    --log-opt max-size=10m --log-opt max-file=3 \
    --health-cmd "wget -qO- http://localhost:${JELLYFIN_PORT}/health || exit 1" \
    --health-interval 30s \
    --tmpfs /tmp:exec,size=2G \
    --tmpfs /config/transcodes:exec,noatime,size=10G \
    -v jellyfin_config:/config:Z -v jellyfin_cache:/config/cache:Z \
    -v "${MEDIA_PATH}":/media:ro,Z \
    -e JELLYFIN_CACHE_DIR=/config/cache -e JELLYFIN_LOG_DIR=/config/log \
    -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,video \
    -e JELLYFIN_PublishedServerUrl="${PUBLISHED_URL}" \
    -e JELLYFIN_BIND_ADDRESS="0.0.0.0:${JELLYFIN_PORT}" \
    "${CONTAINER_IMAGE}"

# ══════════════════════════════════════════════════════════════════════════════
# 🔔 WAIT & NOTIFY
# ══════════════════════════════════════════════════════════════════════════════

# Real health-check polling (see wait_healthy above) instead of a fixed
# sleep — avoids announcing success too early, and avoids waiting longer
# than necessary on fast machines.
if wait_healthy; then
    log "INFO" "Jellyfin started successfully — $MSG_URLS"
    notify "Jellyfin" "Started 🚀 with:\n\n${MSG_MODE}\n\n${MSG_URLS}" "$NOTIFY_ICON" 10000
else
    # Error log is length-limited and stripped of control characters before
    # going into the notification, so it can't corrupt or truncate it badly.
    ERROR_LOG=$(podman logs --tail 20 "${CONTAINER_NAME}" 2>&1 \
        | head -c 500 \
        | tr -d '\000-\010\013\014\016-\037' \
        || echo "No logs available - check podman run error")
    log "ERROR" "Failed to start Jellyfin. Last log lines:"
    log "ERROR" "$ERROR_LOG"
    notify "Jellyfin FAILED" "$ERROR_LOG" "$FAIL_ICON"
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# 🧹 WEEKLY CLEANUP (runs in background)
# ══════════════════════════════════════════════════════════════════════════════

# This runs once a week to keep your system clean. Errors are now recorded
# in LOGFILE instead of being silently discarded.
PRUNE_FILE="$XDG_RUNTIME_DIR/${CONTAINER_NAME}-last-prune"
if [[ ! -f "$PRUNE_FILE" ]] || find "$PRUNE_FILE" -mtime +6 | grep -q .; then
    (
        log "INFO" "Running weekly image and volume cleanup..."
        if podman image prune -f --filter "dangling=true" >>"$LOGFILE" 2>&1 && \
           podman volume prune -f --filter "label!=io.podman.annotations.autocreate" >>"$LOGFILE" 2>&1; then
            log "INFO" "Cleanup completed successfully"
        else
            log "WARN" "Cleanup completed with errors — check $LOGFILE"
        fi
        touch "$PRUNE_FILE"
    ) &
fi
