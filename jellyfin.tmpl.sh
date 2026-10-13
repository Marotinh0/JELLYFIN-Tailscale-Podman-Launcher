#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# 🎬 JELLYFIN + Tailscale + Podman (rootless) — @@FLAVOR@@ edition   v@@VERSION@@
# ──────────────────────────────────────────────────────────────────────────────
# A one-file launcher that runs Jellyfin in a hardened, ROOTLESS Podman
# container with GPU transcoding, optional Tailscale remote access, automatic
# updates (with a config backup first), desktop notifications and safety checks.
#
# Project : https://github.com/Marotinh0/JELLYFIN-Tailscale-Podman-Launcher
# GPU     : @@GPU_LINE@@
#
# ✨ FEATURES
#   • Toggle from a desktop icon: click = start, click again = stop
#   • Tailscale IP auto-detected → watch from anywhere, no port forwarding
#   • Hardware transcoding: @@GPU_FEATURE@@
#   • Hardened container: your own UID (never root), ALL capabilities dropped,
#     no privilege escalation, memory/CPU/PID limits, read-only media mounts,
#     ports bound to specific IPs only (never 0.0.0.0), optional read-only rootfs
#   • Safe updates: pulls the newest image, and BEFORE running a new version it
#     backs up your Jellyfin config/database (a major upgrade can migrate the
#     database in a way that cannot be undone)
#   • Media-drive guard: refuses to start if your drive is unplugged/empty, so
#     Jellyfin never "forgets" your library
#   • Real health check (polls Jellyfin) instead of a blind `sleep`
#   • Pasta networking (fast) with a Slirp fallback
#   • Log file with rotation + journald + desktop notifications
#   • Everything is configurable with environment variables (no editing needed)
#
# 📋 QUICK START
#   1. Install the requirements (see README.md): podman, passt, crun, curl,
#      libnotify (optional), tailscale (optional), @@GPU_REQ@@
#   2. Save this file as ~/bin/@@FILENAME@@  and run:  chmod +x ~/bin/@@FILENAME@@
#   3. Tell it where your media is (pick ONE way):
#        a) edit MEDIA_PATH below, or
#        b) export JELLYFIN_MEDIA_PATH="/path/to/your/media"
#   4. Test it:      @@FILENAME@@ --dry-run      (prints the podman command, changes nothing)
#   5. Run it:       @@FILENAME@@                (first run: open http://localhost:8096)
#   6. Optional: create a desktop icon (see the .desktop file in the repo).
#
# 📖 COMMANDS  (run `@@FILENAME@@ help` to see them again)
#   toggle   (default) start if stopped, stop if running — what the icon does
#   start    start (does nothing if it is already running)
#   stop     stop cleanly
#   restart  stop + start
#   update   force-pull the newest image (+ config backup) and restart
#   status   show state, health, uptime and URLs   (exit code 3 when stopped)
#   logs     follow the container logs (Ctrl+C to leave)
#   backup   export the config volume to a compressed file (Jellyfin must be stopped)
#   restore FILE   replace the config volume with a backup (asks for confirmation)
#   help | --version
#   --dry-run   print the exact `podman run` command and exit — no pull, no
#               backup, no container. Great for reviewing what will happen.
# ══════════════════════════════════════════════════════════════════════════════

# SAFETY SETTINGS
#   -E            the ERR trap also works inside functions
#   -e            exit immediately if a command fails
#   -u            using an unset variable is an error
#   -o pipefail   a failing command inside a pipe fails the whole pipe
# IFS (word splitting) is limited to newline/tab so paths with SPACES are safe.
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="@@VERSION@@"

# ══════════════════════════════════════════════════════════════════════════════
# 🛠️  USER CONFIGURATION — the ONLY section you may want to edit
#     Every setting can ALSO be overridden from the terminal without editing the
#     file, for example:
#         JELLYFIN_MEDIA_PATH="/mnt/media" JELLYFIN_MEMORY=12g @@FILENAME@@
#     (or `export` them in ~/.bashrc / the .desktop file / a systemd unit)
# ══════════════════════════════════════════════════════════════════════════════

# ── Your media ───────────────────────────────────────────────────────────────

# MEDIA_PATH  ←←← THE MOST IMPORTANT SETTING ←←←
# Full path of the folder that holds your movies/TV/music. It is mounted
# READ-ONLY inside the container at /media, so Jellyfin can never modify or
# delete your files. When you create libraries in Jellyfin, browse to /media.
# The script refuses to start if the folder is missing, unmounted, or EMPTY
# (an unplugged drive would otherwise give Jellyfin an empty library).
# Examples:
#   MEDIA_PATH="/mnt/media"
#   MEDIA_PATH="/run/media/$(id -un)/MyDrive"
#   MEDIA_PATH="$HOME/Videos"
MEDIA_PATH="${JELLYFIN_MEDIA_PATH:-/CHANGE/THIS/TO/YOUR/MEDIA/PATH}"

# MEDIA_PATH_2 (optional): a second folder/drive, mounted read-only at /media2.
# Leave empty to disable. If it is set but the drive is unplugged, the server
# still starts (with a warning) without it — one missing drive must not take
# your main library down too.
MEDIA_PATH_2="${JELLYFIN_MEDIA_PATH_2:-}"

# ── Container ────────────────────────────────────────────────────────────────

# CONTAINER_IMAGE: which image to run. For the strictest setup, pin a version
# (docker.io/jellyfin/jellyfin:10.11.0) or a digest (…jellyfin@sha256:…) and
# set AUTO_PULL=false, so nothing ever changes unless YOU decide it.
CONTAINER_IMAGE="${JELLYFIN_IMAGE:-docker.io/jellyfin/jellyfin:latest}"

# CONTAINER_NAME: change only if you want several Jellyfin instances.
CONTAINER_NAME="${JELLYFIN_CONTAINER_NAME:-jellyfin}"

# AUTO_PULL: download the newest image at every start (true/false). Set to
# "false" on a metered connection or when you pin a version.
AUTO_PULL="${JELLYFIN_AUTO_PULL:-true}"

# ── Network ──────────────────────────────────────────────────────────────────

# JELLYFIN_PORT: port on THIS machine (inside the container it is always 8096).
JELLYFIN_PORT="${JELLYFIN_PORT:-8096}"

# NET_MODE: how the container reaches the internet.
#   "pasta" = modern, fast, recommended (default in Podman 5)
#   "slirp" = older fallback — use it if pasta gives you network problems
NET_MODE="${JELLYFIN_NET_MODE:-pasta}"

# LAN_ACCESS: also listen on this machine's LAN address (so TVs/phones on your
# home network can connect). "false" = only localhost + Tailscale.
LAN_ACCESS="${JELLYFIN_LAN_ACCESS:-true}"

# DISCOVERY: publish UDP 7359 so Jellyfin apps can auto-discover the server.
# Discovery uses broadcasts, which a port bound to a single IP usually does NOT
# receive — so it often does nothing here. Off by default; apps can still
# connect by typing the address.
DISCOVERY="${JELLYFIN_DISCOVERY:-false}"

# ALLOW_HOST_ACCESS: lets the container open connections to services running on
# THIS machine (pasta --map-gw / slirp4netns allow_host_loopback). Jellyfin does
# not need it. With "false", a compromised container cannot reach anything
# listening on your loopback (databases, dev servers…). Enable only if a plugin
# must talk to something on this machine (Sonarr, Jellyseerr…).
ALLOW_HOST_ACCESS="${JELLYFIN_ALLOW_HOST_ACCESS:-false}"

# EXPECTED_LAN_SUBNET (optional): a prefix such as "192.168.1." — if the detected
# LAN IP is outside it, a warning is logged (useful when a VPN/exit node steals
# the default route and your firewall rules no longer match). Empty = no check.
EXPECTED_LAN_SUBNET="${JELLYFIN_LAN_SUBNET:-}"

# ── Resource limits ──────────────────────────────────────────────────────────
# MEMORY_LIMIT must cover more than the Jellyfin process: --shm-size and the
# RAM-backed /tmp and transcode folders count against it too. The script warns
# you if SHM_SIZE + TMP_SIZE (+ TRANSCODE_SIZE when in RAM) exceeds MEMORY_LIMIT.
MEMORY_LIMIT="${JELLYFIN_MEMORY:-8g}"
SHM_SIZE="${JELLYFIN_SHM_SIZE:-2g}"
TMP_SIZE="${JELLYFIN_TMP_SIZE:-1g}"

# CPU_LIMIT: hard cap on CPU cores ("auto" = half of your logical CPUs, min 2).
CPU_LIMIT="${JELLYFIN_CPUS:-auto}"
# CPU_SHARES: relative priority when the CPU is busy (default for any container
# is 1024). 512 lets your games/desktop win over ffmpeg when CPU is scarce.
CPU_SHARES="${JELLYFIN_CPU_SHARES:-512}"
# PIDS_LIMIT: max processes inside the container (fork-bomb protection).
PIDS_LIMIT="${JELLYFIN_PIDS_LIMIT:-4096}"

# ── Transcoding scratch space ────────────────────────────────────────────────
# Jellyfin writes temporary video segments while transcoding.
#   TRANSCODE_MODE="ram"  → a tmpfs in RAM: fastest, zero SSD wear, but it uses
#                           RAM (up to TRANSCODE_SIZE) — see MEMORY_LIMIT above.
#   TRANSCODE_MODE="disk" → a Podman volume on disk: no RAM use, slower, writes
#                           to your SSD/HDD.
# ⚠️  Then set the SAME path in Jellyfin: Dashboard → Playback → Transcoding →
#     "Transcode path" = TRANSCODE_PATH (default /config/transcodes).
TRANSCODE_MODE="${JELLYFIN_TRANSCODE_MODE:-ram}"
TRANSCODE_SIZE="${JELLYFIN_TRANSCODE_SIZE:-4g}"
TRANSCODE_PATH="${JELLYFIN_TRANSCODE_PATH:-/config/transcodes}"

# ── Hardening ────────────────────────────────────────────────────────────────

# READ_ONLY: run with a read-only root filesystem (only /config, /config/cache,
# /tmp and the transcode folder stay writable). Safer, but not tested with every
# plugin: try it, and set it back to "false" if something breaks.
READ_ONLY="${JELLYFIN_READ_ONLY:-false}"

# REQUIRE_GPU: "true" = refuse to start (instead of falling back to software
# transcoding) when the GPU cannot be set up. Handy if your CPU is too slow to
# transcode and you prefer a clear error.
REQUIRE_GPU="${JELLYFIN_REQUIRE_GPU:-false}"

#@if nvidia
# ── NVIDIA GPU (CDI) ─────────────────────────────────────────────────────────
# NVIDIA_DEVICE: the CDI device to pass in. "nvidia.com/gpu=all" = every GPU.
# On a multi-GPU box use e.g. "nvidia.com/gpu=0" (list them with: nvidia-ctk cdi list).
NVIDIA_DEVICE="${JELLYFIN_NVIDIA_DEVICE:-nvidia.com/gpu=all}"
# CDI_DIRS: folders where the CDI spec (nvidia.yaml) lives. Podman reads these two.
CDI_DIRS="${JELLYFIN_CDI_DIRS:-/etc/cdi /var/run/cdi}"
# CDI_AUTOREGEN: if the spec is missing or older than your driver, regenerate it
# automatically with `sudo -n nvidia-ctk cdi generate`. Needs a passwordless
# sudo rule for exactly that command (see README → "NVIDIA setup"). Off by
# default so this script never asks for elevated rights on its own.
CDI_AUTOREGEN="${JELLYFIN_CDI_AUTOREGEN:-false}"
#@else
# ── AMD / Intel GPU (VA-API) ─────────────────────────────────────────────────
# GPU_VENDOR: which GPU to use when the machine has more than one render node
# (typical example: AMD iGPU + dedicated GPU).  amd | intel | any
GPU_VENDOR="${JELLYFIN_GPU_VENDOR:-amd}"
# RENDER_NODE: force a specific node (e.g. /dev/dri/renderD129). Empty = auto-pick
# the first node that matches GPU_VENDOR.
RENDER_NODE="${JELLYFIN_RENDER_NODE:-}"
# Advanced: where to look for the GPU nodes / their vendor IDs (used by tests).
DRI_DIR="${JELLYFIN_DRI_DIR:-/dev/dri}"
SYSFS_DRM="${JELLYFIN_SYSFS_DRM:-/sys/class/drm}"
#@endif

# ── Updates & backups ────────────────────────────────────────────────────────
# BACKUP_BEFORE_UPDATE: when a NEW image has just been pulled, export the config
# volume (library database, users, settings) to BACKUP_DIR before the new
# version touches it. If the backup fails, the start is ABORTED (set this to
# "false" to skip). Only the BACKUP_KEEP newest backups are kept.
BACKUP_BEFORE_UPDATE="${JELLYFIN_BACKUP_BEFORE_UPDATE:-true}"
BACKUP_KEEP="${JELLYFIN_BACKUP_KEEP:-3}"
BACKUP_DIR="${JELLYFIN_BACKUP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/jellyfin-backups}"

# ── Waiting for Jellyfin ─────────────────────────────────────────────────────
# Instead of a fixed `sleep`, the script asks Jellyfin "are you up?" every
# HEALTH_INTERVAL seconds. Normal starts get a short timeout; the start that
# follows an image update gets a long one (one-time database migration).
# Timeout reached + container still running = counted as success.
HEALTH_TIMEOUT_NORMAL="${JELLYFIN_HEALTH_TIMEOUT:-45}"
HEALTH_TIMEOUT_AFTER_UPDATE="${JELLYFIN_HEALTH_TIMEOUT_UPDATE:-180}"
HEALTH_INTERVAL=2
# STOP_TIMEOUT: seconds Jellyfin gets to finish cleanly before being killed.
STOP_TIMEOUT="${JELLYFIN_STOP_TIMEOUT:-20}"

# TZ_VALUE: timezone passed to the container (so schedules and log times match
# your machine). Empty = auto-detect with timedatectl.
TZ_VALUE="${JELLYFIN_TZ:-}"

# ══════════════════════════════════════════════════════════════════════════════
# 🖥️  SYSTEM SETUP — no changes needed below this line
# ══════════════════════════════════════════════════════════════════════════════

# This launcher is for ROOTLESS Podman: running it as root would defeat the
# whole isolation model.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "Do not run this script as root — it is meant for rootless Podman." >&2
    exit 1
fi

# A fixed PATH: nothing placed earlier in your own PATH (or in a launcher's
# environment) can silently replace podman, tailscale, etc.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

# Runtime directory (created and owned by systemd-logind: we never create it).
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR
if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
    echo "Runtime dir $XDG_RUNTIME_DIR not found — log in with a normal user session first." >&2
    exit 1
fi
# Needed so notify-send reaches your desktop when started from an icon/cron.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

NOTIFY_ICON="jellyfin"
FAIL_ICON="error"

# Named volumes (they survive deleting the container).
CONFIG_VOLUME="jellyfin_config"
CACHE_VOLUME="jellyfin_cache"
TRANSCODE_VOLUME="jellyfin_transcodes"

# Port the container itself listens on (never changes).
CONTAINER_PORT=8096

# State directory: log file and the "last cleanup" marker. It lives in your home
# (not in the RAM-backed runtime dir) so the history survives a reboot.
STATE_DIR="${JELLYFIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/jellyfin-start}"
# shellcheck disable=SC2174  # -m applies to the final directory only, which is what we want
mkdir -p -m 700 "$STATE_DIR"
LOGFILE="$STATE_DIR/${CONTAINER_NAME}.log"
[[ -e "$LOGFILE" ]] || install -m 600 /dev/null "$LOGFILE"
chmod 600 "$LOGFILE"

# Simple log rotation: above 1 MiB, keep only the last 2000 lines.
if [[ "$(stat -c %s "$LOGFILE")" -gt 1048576 ]]; then
    ( umask 077; tail -n 2000 "$LOGFILE" > "$LOGFILE.tmp" ) && mv -f "$LOGFILE.tmp" "$LOGFILE"
fi

LOCKDIR="$XDG_RUNTIME_DIR/${CONTAINER_NAME}-start.lock"
LOCK_HELD=false
DRY_RUN=false
CMD="toggle"
RESTORE_FILE=""
RESTORE_TMP=""

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

# log LEVEL MESSAGE... — to the terminal, to LOGFILE and to journald
# (read it later with: journalctl --user -t jellyfin-start).
log() {
    local level="$1"; shift
    local line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$line" | tee -a "$LOGFILE" >&2 || true
    logger -t "jellyfin-start" "[$level] $*" 2>/dev/null || true
}

# notify TITLE BODY [ICON] [EXPIRE_MS] — desktop notification; silently skipped
# when there is no graphical session or notify-send is not installed.
notify() {
    local title="$1" body="$2" icon="${3:-$NOTIFY_ICON}" expire="${4:-5000}"
    $DRY_RUN && return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    # strip control characters (keeps newline and tab) that could break the popup
    body="$(printf '%s' "$body" | tr -d '\000-\010\013\014\016-\037')"
    notify-send "$title" "$body" -i "$icon" --expire-time="$expire" 2>/dev/null || true
}

# die MESSAGE... — log + notify + exit 1
die() {
    log "ERROR" "$*"
    notify "Jellyfin ERROR" "$*" "$FAIL_ICON" 10000
    exit 1
}

# Any unexpected failure (set -e) leaves a trace instead of dying silently.
on_error() {
    local code="$1" line="$2"
    trap - ERR
    log "ERROR" "Unexpected failure (exit code $code) at line $line — see $LOGFILE"
    notify "Jellyfin FAILED" "Unexpected error at line $line (exit $code)."$'\n'"Log: $LOGFILE" "$FAIL_ICON" 10000
}
trap 'on_error $? $LINENO' ERR

# Always release the lock and delete temp files, even after a crash.
on_exit() {
    if $LOCK_HELD; then rm -rf "$LOCKDIR"; fi
    if [[ -n "$RESTORE_TMP" ]]; then rm -f -- "$RESTORE_TMP"; fi
}
trap on_exit EXIT

is_true()  { case "${1,,}" in true|1|yes|y|on) return 0 ;; *) return 1 ;; esac; }
is_uint()  { [[ "$1" =~ ^[0-9]+$ ]]; }
is_size()  { [[ "$1" =~ ^[0-9]+[kKmMgG]$ ]]; }

# to_mib 4g → 4096   (used for the memory sanity check)
to_mib() {
    local num="${1%[kKmMgG]}" unit="${1: -1}"
    case "${unit,,}" in
        k) echo $(( 10#$num / 1024 )) ;;
        m) echo $(( 10#$num )) ;;
        g) echo $(( 10#$num * 1024 )) ;;
    esac
}

valid_ipv4() {
    local ip="$1" octet
    local -a parts
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a parts <<< "$ip"
    for octet in "${parts[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
}

# acquire_lock — stops the script from running twice at once. A lock left by a
# crashed run (dead PID) is detected and replaced.
acquire_lock() {
    local pid
    if mkdir "$LOCKDIR" 2>/dev/null; then
        :
    else
        pid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
        log "WARN" "Removing a stale lock (previous PID: ${pid:-unknown})"
        rm -rf "$LOCKDIR"
        mkdir "$LOCKDIR" 2>/dev/null || return 1
    fi
    echo "$$" > "$LOCKDIR/pid"
    LOCK_HELD=true
}

# resolve_cpu_limit — turns CPU_LIMIT="auto" into a number.
resolve_cpu_limit() {
    if [[ -z "$CPU_LIMIT" || "$CPU_LIMIT" == "auto" ]]; then
        local n c
        n="$(nproc 2>/dev/null || echo 2)"
        c=$(( (n + 1) / 2 ))
        if (( c < 2 )); then c=2; fi
        CPU_LIMIT="$c"
    fi
}

# check_deps — required commands are checked BEFORE anything else happens.
check_deps() {
    local missing=() cmd
    for cmd in podman mountpoint ip awk find; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    case "$NET_MODE" in
        pasta) command -v pasta >/dev/null 2>&1 || missing+=("pasta (package: passt)") ;;
        slirp) command -v slirp4netns >/dev/null 2>&1 || missing+=("slirp4netns") ;;
    esac
    if (( ${#missing[@]} > 0 )); then
        die "Missing required dependencies: ${missing[*]}"
    fi
    # Optional
    command -v notify-send >/dev/null 2>&1 || log "WARN" "notify-send not found — no desktop notifications (package: libnotify)"
    command -v tailscale   >/dev/null 2>&1 || log "WARN" "tailscale not found — remote access disabled (local/LAN only)"
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log "WARN" "Neither curl nor wget found — health checks will use 'podman healthcheck run'"
    fi
}

# validate_config — catches typos before "podman run" blows up.
# shellcheck disable=SC2015  # "A && B || die": die exits, so this is deliberate
validate_config() {
    resolve_cpu_limit
    is_uint "$JELLYFIN_PORT" && (( JELLYFIN_PORT >= 1024 && JELLYFIN_PORT <= 65535 )) \
        || die "Invalid JELLYFIN_PORT: '$JELLYFIN_PORT' (use 1024-65535)"
    is_size "$MEMORY_LIMIT" || die "Invalid MEMORY_LIMIT: '$MEMORY_LIMIT' (e.g. 8g)"
    is_size "$SHM_SIZE"     || die "Invalid SHM_SIZE: '$SHM_SIZE' (e.g. 2g)"
    is_size "$TMP_SIZE"     || die "Invalid TMP_SIZE: '$TMP_SIZE' (e.g. 1g)"
    is_size "$TRANSCODE_SIZE" || die "Invalid TRANSCODE_SIZE: '$TRANSCODE_SIZE' (e.g. 4g)"
    # decimals are checked with awk (bc is not on every minimal system)
    [[ "$CPU_LIMIT" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v n="$CPU_LIMIT" 'BEGIN { exit !(n > 0) }' \
        || die "Invalid CPU_LIMIT: '$CPU_LIMIT' (a number such as 4, or 'auto')"
    is_uint "$CPU_SHARES" && (( CPU_SHARES >= 2 )) || die "Invalid CPU_SHARES: '$CPU_SHARES'"
    is_uint "$PIDS_LIMIT" && (( PIDS_LIMIT >= 64 )) || die "Invalid PIDS_LIMIT: '$PIDS_LIMIT'"
    is_uint "$BACKUP_KEEP" && (( BACKUP_KEEP >= 1 )) || die "Invalid BACKUP_KEEP: '$BACKUP_KEEP'"
    is_uint "$STOP_TIMEOUT" || die "Invalid STOP_TIMEOUT: '$STOP_TIMEOUT'"
    is_uint "$HEALTH_TIMEOUT_NORMAL" && is_uint "$HEALTH_TIMEOUT_AFTER_UPDATE" \
        || die "Invalid health timeout values"
    [[ "$NET_MODE" == "pasta" || "$NET_MODE" == "slirp" ]] \
        || die "Invalid NET_MODE: '$NET_MODE' (use pasta or slirp)"
    [[ "$TRANSCODE_MODE" == "ram" || "$TRANSCODE_MODE" == "disk" ]] \
        || die "Invalid TRANSCODE_MODE: '$TRANSCODE_MODE' (use ram or disk)"
    [[ "$TRANSCODE_PATH" == /* ]] || die "TRANSCODE_PATH must be an absolute path inside the container"
    [[ "$CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] \
        || die "Invalid CONTAINER_NAME: '$CONTAINER_NAME'"
#@if amd
    case "$GPU_VENDOR" in amd|intel|any) ;; *) die "Invalid GPU_VENDOR: '$GPU_VENDOR' (use amd, intel or any)" ;; esac
#@endif

    [[ "$MEDIA_PATH" != /CHANGE/THIS/* ]] \
        || die "MEDIA_PATH is not set. Edit it in the script or run: JELLYFIN_MEDIA_PATH=/your/media $0"
    [[ "$MEDIA_PATH" == /* ]] || die "MEDIA_PATH must be an absolute path"
    # ':' would break the "-v host:container" syntax
    [[ "$MEDIA_PATH" != *:* ]] || die "MEDIA_PATH must not contain ':'"
    if [[ -n "$MEDIA_PATH_2" ]]; then
        [[ "$MEDIA_PATH_2" == /* && "$MEDIA_PATH_2" != *:* ]] \
            || die "MEDIA_PATH_2 must be an absolute path without ':'"
    fi
    # NOTE: the paths' EXISTENCE is checked right before the container starts,
    # with a clear "media folder not found" message.

    # Memory sanity check (warning only): RAM-backed mounts count against --memory.
    local need
    need=$(( $(to_mib "$SHM_SIZE") + $(to_mib "$TMP_SIZE") ))
    if [[ "$TRANSCODE_MODE" == "ram" ]]; then need=$(( need + $(to_mib "$TRANSCODE_SIZE") )); fi
    if (( need > $(to_mib "$MEMORY_LIMIT") )); then
        log "WARN" "SHM + TMP$( [[ "$TRANSCODE_MODE" == "ram" ]] && echo ' + TRANSCODE' ) sizes (${need} MiB worst case) exceed MEMORY_LIMIT ($MEMORY_LIMIT) — the container could be OOM-killed under heavy transcoding. Raise JELLYFIN_MEMORY or lower the tmpfs sizes."
    fi
}

# media_available PATH — true if PATH is a mount point, or a folder that is
# not empty (an empty leftover mount folder means the drive is NOT there).
media_available() {
    local p="$1"
    mountpoint -q -- "$p" 2>/dev/null && return 0
    [[ -d "$p" ]] || return 1
    [[ -n "$(find "$p" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

is_running() {
    podman ps --filter "name=^${CONTAINER_NAME}\$" --filter "status=running" \
        --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"
}

# probe_health — ask Jellyfin from the HOST side (does not depend on wget/curl
# existing inside the image).
probe_health() {
    local url="http://127.0.0.1:${JELLYFIN_PORT}/health"
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 3 -o /dev/null "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 3 -O /dev/null "$url" 2>/dev/null
    else
        podman healthcheck run "$CONTAINER_NAME" >/dev/null 2>&1
    fi
}

# wait_healthy TIMEOUT — polls until Jellyfin answers or TIMEOUT seconds pass.
# Timeout + container still running = success (a slow first boot is normal).
wait_healthy() {
    local timeout="$1" elapsed=0
    log "INFO" "Waiting for Jellyfin to become healthy (timeout: ${timeout}s)..."
    while (( elapsed < timeout )); do
        if probe_health; then
            log "INFO" "Jellyfin responded after ${elapsed}s"
            return 0
        fi
        sleep "$HEALTH_INTERVAL"
        # "|| true": an arithmetic expression that evaluates to 0 returns exit
        # code 1, which would trigger "set -e".
        (( elapsed += HEALTH_INTERVAL )) || true
    done
    log "WARN" "Jellyfin did not respond within ${timeout}s — checking if the process is still alive"
    is_running
}

# ══════════════════════════════════════════════════════════════════════════════
# 📦 UPDATE, BACKUP & RESTORE
# ══════════════════════════════════════════════════════════════════════════════

IMAGE_UPDATED=false

pull_image() {
    is_true "$AUTO_PULL" || { log "INFO" "AUTO_PULL disabled — using the local image"; return 0; }
    log "INFO" "Checking for image update: $CONTAINER_IMAGE"
    local old_id new_id
    old_id="$(podman image inspect "$CONTAINER_IMAGE" --format '{{.Id}}' 2>/dev/null || true)"
    if ! podman pull -q "$CONTAINER_IMAGE" >/dev/null 2>>"$LOGFILE"; then
        log "WARN" "Failed to update the image (no internet?) — using the existing local version"
        return 0
    fi
    new_id="$(podman image inspect "$CONTAINER_IMAGE" --format '{{.Id}}' 2>/dev/null || true)"
    if [[ -n "$old_id" && "$old_id" != "$new_id" ]]; then
        IMAGE_UPDATED=true
        log "WARN" "New Jellyfin image pulled — afterwards check Dashboard > Playback > Transcoding (hardware acceleration settings can be reset on big updates)"
    else
        log "INFO" "Image is up to date"
    fi
}

# backup_config_volume — export the config volume (library DB, users, settings)
# to BACKUP_DIR as a compressed file (zstd, or gzip if zstd is missing), mode 600.
backup_config_volume() {
    if ! podman volume exists "$CONFIG_VOLUME" 2>/dev/null; then
        log "INFO" "No '$CONFIG_VOLUME' volume yet — nothing to back up"
        return 0
    fi
    # This function is called as "backup_config_volume || die ...", and bash turns
    # "set -e" OFF inside such a function — so every step that matters has its
    # own explicit "|| return 1".
    # shellcheck disable=SC2174
    mkdir -p -m 700 "$BACKUP_DIR" || return 1
    local stamp tarfile out
    stamp="$(date +%Y%m%d-%H%M%S)"
    tarfile="$BACKUP_DIR/${CONFIG_VOLUME}-${stamp}.tar"
    log "INFO" "Backing up '$CONFIG_VOLUME' → $BACKUP_DIR"
    podman volume export "$CONFIG_VOLUME" --output "$tarfile" || return 1
    if command -v zstd >/dev/null 2>&1; then
        zstd -q -T0 --rm "$tarfile" || return 1
        out="$tarfile.zst"
    else
        gzip -3 "$tarfile" || return 1
        out="$tarfile.gz"
    fi
    chmod 600 "$out" || return 1
    log "INFO" "Backup saved: $out ($(du -h "$out" | cut -f1))"

    # keep only the BACKUP_KEEP newest backups
    local -a old_backups=()
    mapfile -t old_backups < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f -name "${CONFIG_VOLUME}-*.tar.*" -printf '%T@ %p\n' \
            | sort -rn | tail -n "+$((BACKUP_KEEP + 1))" | cut -d' ' -f2-
    )
    local f
    for f in "${old_backups[@]}"; do
        rm -f -- "$f"
        log "INFO" "Removed old backup: $f"
    done
}

cmd_backup() {
    is_running && die "Stop Jellyfin first (a backup of a running database may be inconsistent): $0 stop"
    backup_config_volume || die "Backup FAILED"
}

# cmd_restore FILE — replaces the config volume with the contents of a backup.
cmd_restore() {
    local src="$RESTORE_FILE"
    [[ -n "$src" ]] || die "Usage: $0 restore /path/to/jellyfin_config-YYYYMMDD-HHMMSS.tar.zst"
    [[ -f "$src" && -r "$src" ]] || die "Backup file not found or not readable: $src"
    is_running && die "Stop Jellyfin first: $0 stop"
    [[ -t 0 ]] || die "restore must be run from a terminal (it asks for confirmation)"

    # Decompress to a temp file FIRST: the safety backup below also rotates old
    # backups, and could otherwise delete the very file we are restoring from.
    RESTORE_TMP="$(mktemp -p "$STATE_DIR" restore.XXXXXX)"
    case "$src" in
        *.zst) command -v zstd >/dev/null 2>&1 || die "zstd is needed to read $src"
               zstd -dcq -- "$src" > "$RESTORE_TMP" ;;
        *.gz)  gzip -dc -- "$src" > "$RESTORE_TMP" ;;
        *.tar) cp -- "$src" "$RESTORE_TMP" ;;
        *)     die "Unknown backup format (expected .tar, .tar.gz or .tar.zst): $src" ;;
    esac
    tar -tf "$RESTORE_TMP" >/dev/null 2>&1 || die "This file is not a valid tar archive: $src"

    local answer
    read -r -p "This REPLACES your current Jellyfin config (library, users, settings) with: $src
A safety backup of the current config is made first. Type YES to continue: " answer
    if [[ "$answer" != "YES" ]]; then log "INFO" "Cancelled — nothing was changed."; exit 1; fi

    backup_config_volume || die "Safety backup FAILED — restore cancelled"
    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    podman volume rm -f "$CONFIG_VOLUME" >/dev/null 2>&1 || true
    podman volume create "$CONFIG_VOLUME" >/dev/null
    podman volume import "$CONFIG_VOLUME" "$RESTORE_TMP"
    log "INFO" "Restore complete. Start Jellyfin again with: $0 start"
    notify "Jellyfin" "Config restored from $(basename -- "$src")" "$NOTIFY_ICON"
}

# ══════════════════════════════════════════════════════════════════════════════
# 🎮 GPU
# ══════════════════════════════════════════════════════════════════════════════

# detect_gpu fills three globals:
#   GPU_OK    true/false — was a usable GPU found?
#   GPU_ARGS  extra `podman run` arguments for the GPU (device flags…)
#   GPU_ENV   extra `-e` arguments for the GPU
GPU_OK=false
GPU_ARGS=()
GPU_ENV=()

#@if nvidia
# NVIDIA uses CDI (Container Device Interface): a spec file, generated once by
# `nvidia-ctk`, tells Podman exactly which driver libraries and /dev/nvidia*
# nodes to inject. It must be regenerated after every driver update.

# nvidia_cdi_specs — prints the CDI spec files that describe NVIDIA GPUs.
nvidia_cdi_specs() {
    local -a dirs=()
    local d f
    IFS=' ' read -r -a dirs <<< "$CDI_DIRS"
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*.yaml "$d"/*.yml "$d"/*.json; do
            [[ -f "$f" ]] || continue
            if grep -q 'nvidia\.com/gpu' -- "$f" 2>/dev/null; then printf '%s\n' "$f"; fi
        done
    done
    return 0
}

# cdi_regenerate — optional (CDI_AUTOREGEN=true). Needs a sudoers rule, see README.
cdi_regenerate() {
    local -a dirs=()
    IFS=' ' read -r -a dirs <<< "$CDI_DIRS"
    local out="${dirs[0]}/nvidia.yaml"
    command -v nvidia-ctk >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1 || return 1
    log "INFO" "Regenerating the CDI spec: sudo -n nvidia-ctk cdi generate --output=$out"
    # shellcheck disable=SC2024  # the redirect is meant to run as YOU: it appends to your own log
    sudo -n nvidia-ctk cdi generate --output="$out" >>"$LOGFILE" 2>&1
}

detect_gpu() {
    local -a specs=()
    local driver="" stale=false devname="${NVIDIA_DEVICE#*=}" hint
    hint="Run once:  sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml   (repeat after each driver update)"

    mapfile -t specs < <(nvidia_cdi_specs)
    if command -v nvidia-smi >/dev/null 2>&1; then
        driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null \
                  | head -n1 | tr -d '[:space:]' || true)"
    fi

    if (( ${#specs[@]} == 0 )); then
        log "WARN" "No NVIDIA CDI spec found in: $CDI_DIRS"
        stale=true
    elif [[ -n "$driver" ]] && ! grep -qF -- "$driver" "${specs[@]}" 2>/dev/null; then
        log "WARN" "The CDI spec does not mention your current driver ($driver) — it is probably outdated"
        stale=true
    fi

    # Optionally fix it automatically (never during --dry-run).
    if $stale && is_true "$CDI_AUTOREGEN" && ! $DRY_RUN; then
        if cdi_regenerate; then
            mapfile -t specs < <(nvidia_cdi_specs)
            stale=false
        else
            log "WARN" "Automatic CDI regeneration failed (is the sudoers rule in place? see README)"
        fi
    fi
    if $stale; then log "WARN" "$hint"; fi

    if (( ${#specs[@]} == 0 )); then
        log "WARN" "No GPU available — Jellyfin will use software (CPU) transcoding"
        return 0
    fi
    # Does the spec define the device we were asked to pass in?
    if ! grep -Eq "name\"?:[[:space:]]*[\"']?${devname}[\"']?,?[[:space:]]*\$" "${specs[@]}" 2>/dev/null; then
        log "WARN" "CDI device '$NVIDIA_DEVICE' not found in: ${specs[*]} (list devices with: nvidia-ctk cdi list)"
        return 0
    fi
    GPU_OK=true
    GPU_ARGS=(--device "$NVIDIA_DEVICE")
    # shellcheck disable=SC2054  # the commas are part of the capability list, not separators
    GPU_ENV=(-e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,video)
    log "INFO" "NVIDIA GPU ready via CDI: $NVIDIA_DEVICE${driver:+ (driver $driver)}"
}
#@else
# AMD (and Intel) GPUs use VA-API through the kernel "render node"
# (/dev/dri/renderD128 and friends). That is the ONLY device the container gets:
# the /dev/dri/card* nodes can change display settings and are NOT exposed.

# gpu_vendor_id NODE — prints the PCI vendor id of a render node (0x1002 = AMD,
# 0x8086 = Intel, 0x10de = NVIDIA).
gpu_vendor_id() {
    cat "$SYSFS_DRM/$(basename -- "$1")/device/vendor" 2>/dev/null || true
}

detect_gpu() {
    local node="" want="" n v
    if [[ -n "$RENDER_NODE" ]]; then
        [[ -e "$RENDER_NODE" ]] || { log "WARN" "RENDER_NODE '$RENDER_NODE' does not exist"; return 0; }
        node="$RENDER_NODE"
    else
        case "$GPU_VENDOR" in
            amd)   want="0x1002" ;;
            intel) want="0x8086" ;;
        esac
        while IFS= read -r n; do
            [[ -n "$n" ]] || continue
            v="$(gpu_vendor_id "$n")"
            if [[ -z "$want" || "$v" == "$want" ]]; then node="$n"; break; fi
        done < <(find "$DRI_DIR" -maxdepth 1 -name 'renderD*' 2>/dev/null | sort)
    fi

    if [[ -z "$node" ]]; then
        log "WARN" "No matching GPU render node in $DRI_DIR (vendor filter: $GPU_VENDOR) — Jellyfin will use software (CPU) transcoding"
        return 0
    fi
    log "INFO" "GPU render node: $node (vendor $(gpu_vendor_id "$node"))"
    log "INFO" "In Jellyfin: Dashboard → Playback → Transcoding → Hardware acceleration = VA-API, device = $node"

    if [[ ! -r "$node" || ! -w "$node" ]]; then
        log "WARN" "No read/write permission on $node — add your user to the 'render' group: sudo usermod -aG render,video \$USER (then log out and back in)"
    fi
    # "--group-add keep-groups" only forwards the groups your CURRENT session has.
    if ! id -nG | tr ' ' '\n' | grep -qxE 'render|video'; then
        log "WARN" "This session is not in the 'render' or 'video' group — if hardware transcoding fails, log out/in after adding it"
    fi
    GPU_OK=true
    GPU_ARGS=(--device "$node")
    GPU_ENV=()
}
#@endif

# warn_if_not_crun — "--group-add keep-groups" (needed to reach the GPU as a
# member of the render/video group) only works with the crun OCI runtime.
warn_if_not_crun() {
    local rt
    rt="$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null || true)"
    if [[ -n "$rt" && "$rt" != "crun" ]]; then
        log "WARN" "Podman is using the '$rt' runtime. GPU group access ('keep-groups') requires crun — install it and make it the default runtime if the GPU does not work"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 🌐 NETWORK DETECTION
# ══════════════════════════════════════════════════════════════════════════════

detect_network() {
    TS_IP=""
    if command -v tailscale >/dev/null 2>&1; then
        TS_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
        valid_ipv4 "$TS_IP" || TS_IP=""
        if [[ -z "$TS_IP" ]]; then
            log "INFO" "Tailscale is installed but not connected (no IPv4) — run: tailscale up"
        fi
    fi

    LAN_IP=""
    if is_true "$LAN_ACCESS"; then
        LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null \
            | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
        if ! valid_ipv4 "$LAN_IP"; then
            [[ -n "$LAN_IP" ]] && log "WARN" "Detected LAN IP '$LAN_IP' looks invalid"
            LAN_IP=""
        fi
        # With a Tailscale exit node the "default route" address IS the Tailscale
        # address — binding it twice would make podman fail.
        if [[ -n "$LAN_IP" && "$LAN_IP" == "$TS_IP" ]]; then LAN_IP=""; fi
        if [[ -n "$LAN_IP" && -n "$EXPECTED_LAN_SUBNET" && "$LAN_IP" != "${EXPECTED_LAN_SUBNET}"* ]]; then
            log "WARN" "LAN IP ($LAN_IP) is outside the expected subnet (${EXPECTED_LAN_SUBNET}*) — firewall rules may block it (VPN/exit node?)"
        fi
    fi

    # Network mode. Host access stays OFF unless ALLOW_HOST_ACCESS=true.
    if [[ "$NET_MODE" == "pasta" ]]; then
        NET_OPT="pasta"
        is_true "$ALLOW_HOST_ACCESS" && NET_OPT="pasta:--map-gw"
        MSG_MODE="🍝 Pasta"
    else
        NET_OPT="slirp4netns"
        is_true "$ALLOW_HOST_ACCESS" && NET_OPT="slirp4netns:allow_host_loopback=true"
        MSG_MODE="🛡️ Slirp"
    fi

    # Published ports (an array: each flag stays ONE argument).
    # We bind to specific addresses — never 0.0.0.0 — so Jellyfin is reachable
    # only from this machine, your LAN address and your Tailscale address.
    PORT_ARGS=("-p" "127.0.0.1:${JELLYFIN_PORT}:${CONTAINER_PORT}")
    MSG_URLS="🖥️ Local: http://127.0.0.1:${JELLYFIN_PORT}"
    if [[ -n "$LAN_IP" ]]; then
        PORT_ARGS+=("-p" "${LAN_IP}:${JELLYFIN_PORT}:${CONTAINER_PORT}")
        MSG_URLS+=$'\n'"🏠 LAN: http://${LAN_IP}:${JELLYFIN_PORT}"
        if is_true "$DISCOVERY"; then
            PORT_ARGS+=("-p" "${LAN_IP}:7359:7359/udp")
        fi
    elif is_true "$LAN_ACCESS"; then
        log "WARN" "Could not detect a LAN IP — LAN access and discovery disabled"
    fi
    if [[ -n "$TS_IP" ]]; then
        PORT_ARGS+=("-p" "${TS_IP}:${JELLYFIN_PORT}:${CONTAINER_PORT}")
        MSG_URLS+=$'\n'"🌐 Tailscale: http://${TS_IP}:${JELLYFIN_PORT}"
        log "INFO" "Tailscale detected: $TS_IP"
    else
        log "INFO" "No Tailscale address — remote access only through your LAN"
    fi

    # The address Jellyfin advertises to clients: Tailscale > LAN > localhost.
    PUBLISHED_URL="http://${TS_IP:-${LAN_IP:-127.0.0.1}}:${JELLYFIN_PORT}"
}

# ══════════════════════════════════════════════════════════════════════════════
# 🚀 COMMANDS
# ══════════════════════════════════════════════════════════════════════════════

stop_container() {
    log "INFO" "Stopping the container (up to ${STOP_TIMEOUT}s)..."
    podman stop "$CONTAINER_NAME" --time "$STOP_TIMEOUT" >/dev/null
    log "INFO" "Container stopped successfully"
    notify "Jellyfin stopped" "Server shut down cleanly" "$NOTIFY_ICON"
}

cmd_status() {
    if is_running; then
        local health started
        health="$(podman inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "?")"
        started="$(podman inspect --format '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null || echo "?")"
        detect_network
        printf 'Jellyfin is RUNNING\n  health : %s\n  started: %s\n  image  : %s\n%s\n' \
            "$health" "$started" "$CONTAINER_IMAGE" "$MSG_URLS"
        return 0
    fi
    echo "Jellyfin is STOPPED"
    return 3
}

cmd_logs() {
    podman container exists "$CONTAINER_NAME" 2>/dev/null || die "Container '$CONTAINER_NAME' does not exist yet"
    exec podman logs -f --tail 200 "$CONTAINER_NAME"
}

# build_run_args USE_GPU(true|false) — assembles the whole `podman run` command
# in the RUN_ARGS array (an array keeps every flag as one safe argument).
#
# Hardening in short: runs as YOUR user (not root), ALL capabilities dropped (a
# non-root process does not need any), no privilege gain, no swap, pids/cpu/
# memory limits, media mounted read-only, only the GPU device, ports bound to
# specific IPs. Flags, grouped by purpose:
#   IDENTITY   --userns keep-id --user UID:GID   your UID/GID inside the container,
#              so files are readable without root
#              --group-add keep-groups           keep your supplementary groups
#              (render/video) → needed for GPU device access (requires crun)
#   SECURITY   --cap-drop=ALL, no-new-privileges
#   LIMITS     --memory/--memory-swap (same value = no swap), --shm-size, --cpus,
#              --cpu-shares, --pids-limit
#   RESTART    --restart on-failure:5   restarts after a crash (max 5 times) but
#              NOT after a clean stop, so the toggle works
#   LOGS       rotated: 3 files × 10 MB
#   HEALTH     Podman checks /health every 30 s
#   SCRATCH    --tmpfs /tmp (exec is needed by Jellyfin's helper binaries) and
#              the transcode folder (RAM or disk, see TRANSCODE_MODE)
build_run_args() {
    local use_gpu="$1"
    # shellcheck disable=SC2054  # the commas are mount options (exec,nosuid,...), not separators
    RUN_ARGS=(
        run -d
        --name "$CONTAINER_NAME" --replace
        --userns keep-id --user "$(id -u):$(id -g)" --group-add keep-groups
        --security-opt no-new-privileges:true --cap-drop=ALL
        --memory "$MEMORY_LIMIT" --memory-swap "$MEMORY_LIMIT" --shm-size "$SHM_SIZE"
        --cpus "$CPU_LIMIT" --cpu-shares "$CPU_SHARES" --pids-limit "$PIDS_LIMIT"
        --network "$NET_OPT" "${PORT_ARGS[@]}"
        --restart on-failure:5 --stop-timeout "$STOP_TIMEOUT"
        --log-opt max-size=10m --log-opt max-file=3
        --health-cmd "curl -fsS http://localhost:${CONTAINER_PORT}/health >/dev/null 2>&1 || wget -qO /dev/null http://localhost:${CONTAINER_PORT}/health || exit 1"
        --health-interval 30s --health-start-period 60s --health-retries 3
        --tmpfs "/tmp:exec,nosuid,nodev,size=${TMP_SIZE}"
        -v "${CONFIG_VOLUME}:/config" -v "${CACHE_VOLUME}:/config/cache"
        -v "${MEDIA_PATH}:/media:ro"
    )
    # Transcode folder
    if [[ "$TRANSCODE_MODE" == "ram" ]]; then
        RUN_ARGS+=(--tmpfs "${TRANSCODE_PATH}:exec,nosuid,nodev,noatime,size=${TRANSCODE_SIZE}")
    else
        RUN_ARGS+=(-v "${TRANSCODE_VOLUME}:${TRANSCODE_PATH}")
    fi
    # Second media folder (empty array = nothing added)
    RUN_ARGS+=("${SECOND_MEDIA_MOUNT[@]}")
    # GPU
    if [[ "$use_gpu" == "true" ]]; then
        RUN_ARGS+=("${GPU_ARGS[@]}" "${GPU_ENV[@]}")
    fi
    # SELinux: only when it is really enforcing (Fedora/RHEL — not Arch/Debian).
    # The ":Z" relabel flag is deliberately NOT used: on a media drive it would
    # relabel your whole library.
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
        RUN_ARGS+=(--security-opt label=disable)
    fi
    if is_true "$READ_ONLY"; then RUN_ARGS+=(--read-only); fi
    if [[ -n "$TZ_VALUE" ]]; then RUN_ARGS+=(-e "TZ=${TZ_VALUE}"); fi
    RUN_ARGS+=(
        -e JELLYFIN_CACHE_DIR=/config/cache -e JELLYFIN_LOG_DIR=/config/log
        -e "JELLYFIN_PublishedServerUrl=${PUBLISHED_URL}"
        "$CONTAINER_IMAGE"
    )
}

cmd_start() {
    # Make sure the media drive is really there (prevents an empty library).
    if ! media_available "$MEDIA_PATH"; then
        if $DRY_RUN; then
            log "WARN" "Media folder not available (ignored in --dry-run): $MEDIA_PATH"
        else
            die "Media folder not found or empty: $MEDIA_PATH — is the drive plugged in and mounted?"
        fi
    fi

    # The second folder is OPTIONAL: failing the whole server because it is
    # unplugged would also take the main library down.
    SECOND_MEDIA_MOUNT=()
    if [[ -n "$MEDIA_PATH_2" ]]; then
        if media_available "$MEDIA_PATH_2"; then
            SECOND_MEDIA_MOUNT=("-v" "${MEDIA_PATH_2}:/media2:ro")
            log "INFO" "Second media path found: $MEDIA_PATH_2 → /media2"
        else
            log "WARN" "Second media path not found or empty: '$MEDIA_PATH_2' — starting WITHOUT it"
        fi
    fi

    notify "Jellyfin" "Checking for updates and preparing the GPU..." "$NOTIFY_ICON" 2000
    warn_if_not_crun
    detect_gpu
    if ! $GPU_OK && is_true "$REQUIRE_GPU"; then
        if $DRY_RUN; then
            log "WARN" "REQUIRE_GPU=true and no GPU is available (a real start would be refused)"
        else
            die "REQUIRE_GPU=true but no usable GPU was found — not starting. See the warnings above."
        fi
    fi

    if $DRY_RUN; then
        log "INFO" "--dry-run: skipping image pull, volume creation and backup"
    else
        pull_image
        # Named volumes survive even if the container is deleted.
        podman volume create "$CONFIG_VOLUME" >/dev/null 2>&1 || true
        podman volume create "$CACHE_VOLUME"  >/dev/null 2>&1 || true
        if [[ "$TRANSCODE_MODE" == "disk" ]]; then
            podman volume create "$TRANSCODE_VOLUME" >/dev/null 2>&1 || true
        fi
        if $IMAGE_UPDATED && is_true "$BACKUP_BEFORE_UPDATE"; then
            backup_config_volume || die "Backup before the update FAILED — not starting. Fix it, or set JELLYFIN_BACKUP_BEFORE_UPDATE=false to skip."
        fi
    fi

    detect_network

    # Timezone
    if [[ -z "$TZ_VALUE" ]] && command -v timedatectl >/dev/null 2>&1; then
        TZ_VALUE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    fi

    build_run_args "$GPU_OK"

    if $DRY_RUN; then
        printf 'podman'; printf ' %q' "${RUN_ARGS[@]}"; printf '\n'
        return 0
    fi

    log "INFO" "Starting container: $CONTAINER_NAME"
    log "INFO" "Image: $CONTAINER_IMAGE | Host port: $JELLYFIN_PORT | Network: $MSG_MODE | GPU: $GPU_OK | Read-only: $READ_ONLY"

    # Wrapped in "if !" so a failure is caught explicitly (under "set -e" a bare
    # failing command would kill the script with no notification). stderr is
    # folded in so the real reason podman refused to start is captured.
    local run_output
    if ! run_output="$(podman "${RUN_ARGS[@]}" 2>&1)"; then
        log "ERROR" "podman run failed:"
        log "ERROR" "$run_output"
        if $GPU_OK && ! is_true "$REQUIRE_GPU"; then
            # The GPU setup is the most common cause (outdated CDI spec, missing
            # permissions…). Rather than leave you without a server, retry once
            # without the GPU — software transcoding is slower but works.
            log "WARN" "Retrying WITHOUT the GPU (software transcoding) — fix the error above to get hardware acceleration back"
            build_run_args false
            if ! run_output="$(podman "${RUN_ARGS[@]}" 2>&1)"; then
                log "ERROR" "podman run failed again:"
                log "ERROR" "$run_output"
                notify "Jellyfin FAILED" "podman run error: $(printf '%s' "$run_output" | head -c 400)" "$FAIL_ICON" 10000
                exit 1
            fi
            GPU_OK=false
            notify "Jellyfin" "Started WITHOUT GPU acceleration — check the log: $LOGFILE" "$FAIL_ICON" 10000
        else
            notify "Jellyfin FAILED" "podman run error: $(printf '%s' "$run_output" | head -c 400)" "$FAIL_ICON" 10000
            exit 1
        fi
    fi

    local timeout="$HEALTH_TIMEOUT_NORMAL"
    if $IMAGE_UPDATED; then timeout="$HEALTH_TIMEOUT_AFTER_UPDATE"; fi
    if wait_healthy "$timeout"; then
        log "INFO" "Jellyfin started successfully"
        notify "Jellyfin" "Started 🚀 with ${MSG_MODE}"$'\n\n'"${MSG_URLS}" "$NOTIFY_ICON" 10000
    else
        local error_log
        error_log="$(podman logs --tail 20 "$CONTAINER_NAME" 2>&1 | head -c 500 || true)"
        log "ERROR" "Failed to start Jellyfin. Last log lines:"
        log "ERROR" "${error_log:-No logs available}"
        notify "Jellyfin FAILED" "${error_log:-No logs available}" "$FAIL_ICON" 10000
        exit 1
    fi

    weekly_cleanup
}

# weekly_cleanup — removes DANGLING images only (the old image left behind after
# an update). Volumes are never pruned: "podman volume prune" deletes every
# unused named volume on the system, including other projects' data.
weekly_cleanup() {
    local marker="$STATE_DIR/${CONTAINER_NAME}-last-prune"
    if [[ ! -f "$marker" ]] || [[ -n "$(find "$marker" -mtime +6 -print -quit)" ]]; then
        (
            log "INFO" "Running weekly cleanup of dangling images..."
            if podman image prune -f >>"$LOGFILE" 2>&1; then
                log "INFO" "Cleanup completed"
            else
                log "WARN" "Cleanup finished with errors — check $LOGFILE"
            fi
            touch "$marker"
        ) &
        disown || true
    fi
}

usage() {
    cat <<EOF
Jellyfin + Tailscale + Podman launcher (@@FLAVOR@@) v${SCRIPT_VERSION}

USAGE
  $(basename -- "$0") [COMMAND] [--dry-run]

COMMANDS
  toggle   (default) start if stopped, stop if running — the desktop-icon behaviour
  start    start (does nothing if it is already running)
  stop     stop cleanly
  restart  stop + start
  update   force-pull the newest image (with a config backup) and restart
  status   show state, health, uptime and URLs (exit code 3 if stopped)
  logs     follow the container logs (Ctrl+C to leave)
  backup   export the config volume to ${BACKUP_DIR}
  restore FILE   replace the config volume with a backup (asks for confirmation)
  help, --version

OPTIONS
  --dry-run  print the exact "podman run" command and exit, changing nothing
             (no pull, no backup, no container)

Settings are environment variables (JELLYFIN_MEDIA_PATH, JELLYFIN_MEMORY, …) —
see the USER CONFIGURATION section of this script and the README.
EOF
}

# ══════════════════════════════════════════════════════════════════════════════
# ▶️  MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
    while (( $# > 0 )); do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            toggle|start|stop|restart|update|status|logs|backup) CMD="$1" ;;
            restore)
                CMD="restore"
                if (( $# < 2 )); then echo "restore needs a backup file" >&2; usage >&2; exit 2; fi
                RESTORE_FILE="$2"; shift ;;
            help|-h|--help) usage; exit 0 ;;
            --version|-V)   echo "$SCRIPT_VERSION"; exit 0 ;;
            *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
    if $DRY_RUN; then
        case "$CMD" in
            toggle|start|restart|update) ;;
            *) echo "--dry-run only works with: toggle, start, restart, update" >&2; exit 2 ;;
        esac
    fi

    # Both checks run BEFORE touching anything else on the system.
    check_deps
    validate_config

    case "$CMD" in
        status) cmd_status || exit $? ; exit 0 ;;
        logs)   cmd_logs ;;
    esac

    # Commands that change things: only one at a time.
    if ! acquire_lock; then
        notify "Jellyfin" "Already starting… (wait a moment)" "$NOTIFY_ICON"
        exit 1
    fi
    local dry_note=""
    if $DRY_RUN; then dry_note=" (dry-run)"; fi
    log "INFO" "Script started by $(id -un) (PID $$) — command: ${CMD}${dry_note}"

    case "$CMD" in
        toggle)
            if is_running; then stop_container; else cmd_start; fi ;;
        start)
            if is_running; then log "INFO" "Already running"; notify "Jellyfin" "Already running" "$NOTIFY_ICON"; else cmd_start; fi ;;
        stop)
            if is_running; then stop_container; else log "INFO" "Already stopped"; fi ;;
        restart)
            if is_running; then stop_container; fi
            cmd_start ;;
        update)
            AUTO_PULL=true
            if is_running; then stop_container; fi
            cmd_start ;;
        backup)  cmd_backup ;;
        restore) cmd_restore ;;
    esac
}

main "$@"
