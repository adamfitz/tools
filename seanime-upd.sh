#!/usr/bin/env bash
set -Eeuo pipefail

# Seanime update configuration
SERVICE="seanime"
APP_DIR="/opt/seanime"
APP_BIN="/opt/seanime/seanime"
DATA_DIR="/home/shareuser/.config/seanime/"
BACKUP_ROOT="/var/backups/seanime"
HEALTH_URL="http://10.23.0.3:43211/"
RELEASE_API="https://api.github.com/repos/5rahim/seanime/releases/latest"

WORK_DIR=""
BACKUP_DIR=""
SERVICE_STOPPED=0
INSTALL_STARTED=0
UPDATE_SUCCESSFUL=0

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

get_version() {
    local output
    output="$("$1" --help 2>&1)" || true

    if [[ "$output" =~ \│[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*\│ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

rollback() {
    log "Attempting to restore the previous Seanime executable..."

    if [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/seanime" ]]; then
        if install -o root -g root -m 0755 \
            "$BACKUP_DIR/seanime" "${APP_BIN}.rollback"; then
            mv -f "${APP_BIN}.rollback" "$APP_BIN"
            log "Previous executable restored."
        else
            log "CRITICAL: Could not restore the previous executable."
        fi
    else
        log "CRITICAL: Previous executable backup is unavailable."
    fi

    if [[ "$SERVICE_STOPPED" -eq 1 ]]; then
        if systemctl start "$SERVICE"; then
            log "Seanime service restarted after rollback."
        else
            log "CRITICAL: Seanime service failed to start after rollback."
            log "Check: journalctl -u ${SERVICE} -n 100 --no-pager"
        fi
        SERVICE_STOPPED=0
    fi
}

cleanup() {
    local exit_code=$?

    trap - EXIT

    if [[ "$exit_code" -ne 0 &&
          "$INSTALL_STARTED" -eq 1 &&
          "$UPDATE_SUCCESSFUL" -eq 0 ]]; then
        rollback
    elif [[ "$exit_code" -ne 0 &&
            "$SERVICE_STOPPED" -eq 1 ]]; then
        systemctl start "$SERVICE" ||
            log "ERROR: Could not restart Seanime."
    fi

    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi

    exit "$exit_code"
}
trap cleanup EXIT

# Only run as root.
[[ "$EUID" -eq 0 ]] || die "Run this script as root."

# Verify required commands.
for cmd in curl jq tar sha256sum install systemctl find; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Required command not found: $cmd"
done

# Verify the existing installation and intended data directory.
[[ -x "$APP_BIN" ]] || die "Executable not found: $APP_BIN"
[[ -d "$DATA_DIR" ]] || die "Data directory not found: $DATA_DIR"

SERVICE_USER="$(systemctl show "$SERVICE" -p User --value)"
[[ "$SERVICE_USER" == "shareuser" ]] ||
    die "Expected systemd service User=shareuser; found '${SERVICE_USER:-root/default}'."

SERVICE_GROUP="$(systemctl show "$SERVICE" -p Group --value)"
[[ "$SERVICE_GROUP" == "datashare" ]] ||
    die "Expected systemd service Group=datashare; found '${SERVICE_GROUP:-default}'."

SERVICE_EXEC="$(systemctl show "$SERVICE" -p ExecStart --value)"
[[ "$SERVICE_EXEC" == *"$APP_BIN"* &&
   "$SERVICE_EXEC" == *"$DATA_DIR"* ]] ||
    die "Service ExecStart does not match the expected binary and data directory."

CURRENT_VERSION="$(get_version "$APP_BIN")" ||
    die "Could not determine the installed Seanime version."

log "Installed version: $CURRENT_VERSION"
log "Executable: $APP_BIN"
log "Data directory: $DATA_DIR"
log "Service account: ${SERVICE_USER}:${SERVICE_GROUP}"

# Fetch the latest stable release.
WORK_DIR="$(mktemp -d /var/tmp/seanime-update.XXXXXX)"
RELEASE_JSON="${WORK_DIR}/release.json"

log "Checking the latest stable GitHub release..."

curl --fail --silent --show-error --location \
    --retry 3 \
    "$RELEASE_API" \
    -o "$RELEASE_JSON"

TAG="$(jq -er '.tag_name' "$RELEASE_JSON")"
LATEST_VERSION="${TAG#v}"
ASSET_NAME="seanime-${LATEST_VERSION}_Linux_x86_64.tar.gz"

ASSET_URL="$(jq -er --arg name "$ASSET_NAME" \
    '.assets[] | select(.name == $name) | .browser_download_url' \
    "$RELEASE_JSON")" ||
    die "Could not find release archive: $ASSET_NAME"

DIGEST="$(jq -r --arg name "$ASSET_NAME" \
    '.assets[] | select(.name == $name) | .digest // empty' \
    "$RELEASE_JSON")"

[[ "$DIGEST" == sha256:* ]] ||
    die "GitHub did not provide a SHA-256 digest. Nothing has been changed."

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    log "Already running the latest stable release ($CURRENT_VERSION)."
    log "No update required; service and files left untouched."
    exit 0
fi

ARCHIVE="${WORK_DIR}/${ASSET_NAME}"
EXTRACT_DIR="${WORK_DIR}/extracted"

log "Latest version: $LATEST_VERSION"
log "Downloading $ASSET_NAME..."

curl --fail --silent --show-error --location \
    --retry 3 \
    "$ASSET_URL" \
    -o "$ARCHIVE"

EXPECTED_SHA="${DIGEST#sha256:}"
ACTUAL_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"

[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] ||
    die "SHA-256 verification failed. Installation left untouched."

log "Archive SHA-256 verified."

# Reject unsafe archive paths before extraction.
while IFS= read -r entry; do
    case "$entry" in
        /*|..|../*|*/../*|*/..)
            die "Unsafe path in release archive: $entry"
            ;;
    esac
done < <(tar -tzf "$ARCHIVE")

mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

# The release archive does not have to contain an assets directory.
# Find the executable by name and leave all existing installation
# directories, including /opt/seanime/assets, untouched.
mapfile -t BINARIES < <(
    find "$EXTRACT_DIR" -type f -name seanime
)

[[ "${#BINARIES[@]}" -eq 1 ]] ||
    die "Expected exactly one seanime executable in the release archive; found ${#BINARIES[@]}."

NEW_BIN="${BINARIES[0]}"

NEW_VERSION="$(get_version "$NEW_BIN")" ||
    die "Could not determine the downloaded executable version."

[[ "$NEW_VERSION" == "$LATEST_VERSION" ]] ||
    die "Release tag is $LATEST_VERSION but downloaded executable reports $NEW_VERSION."

log "Downloaded executable version verified: $NEW_VERSION"

# Back up the current executable before changing anything.
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"

mkdir -p "$BACKUP_DIR"
cp -a "$APP_BIN" "$BACKUP_DIR/seanime"

log "Executable backup: $BACKUP_DIR/seanime"

# Stop the service before replacing the executable.
log "Stopping Seanime service..."
systemctl stop "$SERVICE"
SERVICE_STOPPED=1

if systemctl is-active --quiet "$SERVICE"; then
    die "Service remains active after stop."
fi

# From this point, any failure triggers rollback.
INSTALL_STARTED=1

install -o root -g root -m 0755 \
    "$NEW_BIN" "${APP_BIN}.new"

mv -f "${APP_BIN}.new" "$APP_BIN"

log "Installed Seanime $NEW_VERSION."
log "Existing assets and data directories were not replaced."

# Start and test the updated service.
log "Starting Seanime service..."
systemctl start "$SERVICE"
SERVICE_STOPPED=0

HEALTHY=0

for _ in $(seq 1 30); do
    if systemctl is-active --quiet "$SERVICE" &&
       curl --fail --silent --output /dev/null \
           --max-time 2 "$HEALTH_URL"; then
        HEALTHY=1
        break
    fi

    sleep 1
done

if [[ "$HEALTHY" -ne 1 ]]; then
    die "Seanime failed its startup or HTTP health check."
fi

# Verify the service is running the expected version.
RUNNING_VERSION="$(get_version "$APP_BIN")" ||
    die "Could not verify the installed version."

[[ "$RUNNING_VERSION" == "$LATEST_VERSION" ]] ||
    die "Version verification failed after installation."

UPDATE_SUCCESSFUL=1

log "Update successful: Seanime $RUNNING_VERSION"
log "HTTP health check passed: $HEALTH_URL"
log "Data directory unchanged: $DATA_DIR"
log "Backup retained: $BACKUP_DIR"
