#!/usr/bin/env bash

set -u

PLAYLIST_URL=""
OUTPUT_DIR="."
ARCHIVE_FILE=""
COOKIES_FILE="$HOME/cookies.txt"

MODE=""
DELETE_DUPLICATES=false
CURRENT_PGID=""

usage() {
  echo "Usage: $0 [OPTIONS] <playlist_or_video_url>"
  echo ""
  echo "Options:"
  echo "  -a, --audio    Download audio only as MP3"
  echo "  -v, --video    Download video with audio"
  echo "  -d, --delete   Delete duplicate MP3 files, keeping the oldest copy"
  echo "  -h, --help     Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 --audio \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --video \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --audio \"https://www.youtube.com/watch?v=XXXX\""
  echo "  $0 --video \"https://www.youtube.com/watch?v=XXXX\""
  echo "  $0 --delete \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --delete \"https://www.youtube.com/watch?v=XXXX\""
}

# ============================================================
# Return true if a filename belongs to a specific YouTube ID.
#
# IMPORTANT:
# Do NOT use:
#
#   find ... -name "*[$ID].*"
#
# because [] is a glob character class.
#
# We instead extract the ID from the literal:
#
#   [VIDEO_ID].extension
#
# ============================================================

is_matching_audio_file() {
  local file="$1"
  local id="$2"
  local base

  base=$(basename "$file")

  [[ "$base" =~ \[${id}\]\.mp3$ ]]
}

is_matching_video_file() {
  local file="$1"
  local id="$2"
  local base

  base=$(basename "$file")

  [[ "$base" =~ \[${id}\]\.(mp4|webm|mkv)$ ]]
}

# ============================================================
# Find an existing MP3 for an exact YouTube ID.
#
# The ID MUST be inside literal square brackets immediately
# before .mp3.
# ============================================================

find_audio_file() {
  local id="$1"
  local file

  while IFS= read -r -d '' file; do
    if is_matching_audio_file "$file" "$id"; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      -name '*.mp3' \
      -print0
  )

  return 1
}

# ============================================================
# Find an existing video for an exact YouTube ID.
#
# Supported containers:
#   .mp4
#   .webm
#   .mkv
#
# The ID MUST be inside literal square brackets immediately
# before the extension.
# ============================================================

find_video_file() {
  local id="$1"
  local file

  while IFS= read -r -d '' file; do
    if is_matching_video_file "$file" "$id"; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      \( \
        -name '*.mp4' \
        -o -name '*.webm' \
        -o -name '*.mkv' \
      \) \
      -print0
  )

  return 1
}

# ============================================================
# Cleanup duplicate MP3 files
#
# Files are duplicates when they contain the same exact
# 11-character YouTube ID in:
#
#   [VIDEO_ID].mp3
#
# The oldest file is kept.
#
# --delete:
#   Delete newer duplicates.
#
# Without --delete:
#   DRY RUN ONLY.
#
# ============================================================

cleanup_duplicates() {
  echo ""
  echo "===================================="
  echo "Checking for duplicate MP3 files"
  echo "===================================="

  declare -A oldest_file
  declare -A oldest_time
  declare -A duplicate_count

  local file
  local id
  local mtime

  while IFS= read -r -d '' file; do

    # Extract exact 11-character YouTube ID from:
    #
    #   anything [VIDEO_ID].mp3
    #
    if [[ "$(basename "$file")" =~ \[([A-Za-z0-9_-]{11})\]\.mp3$ ]]; then
      id="${BASH_REMATCH[1]}"
    else
      continue
    fi

    mtime=$(stat -c '%Y' -- "$file")

    if [[ -z "${oldest_file[$id]+x}" ]]; then

      oldest_file["$id"]="$file"
      oldest_time["$id"]="$mtime"
      duplicate_count["$id"]=1

    else

      duplicate_count["$id"]=$((duplicate_count["$id"] + 1))

      if (( mtime < oldest_time["$id"] )); then
        oldest_file["$id"]="$file"
        oldest_time["$id"]="$mtime"
      fi

    fi

  done < <(
    find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      -name '*.mp3' \
      -print0
  )

  local total=0
  local removed=0
  local count
  local keep
  local file_time
  local file_size

  for id in "${!duplicate_count[@]}"; do

    count="${duplicate_count[$id]}"

    # Not a duplicate.
    (( count > 1 )) || continue

    total=$((total + count - 1))
    keep="${oldest_file[$id]}"

    echo ""
    echo "YouTube ID: $id"
    echo ""
    echo "KEEP (oldest):"
    echo "  $(basename "$keep")"
    echo "  Date: $(stat -c '%y' -- "$keep")"
    echo "  Size: $(stat -c '%s' -- "$keep") bytes"

    while IFS= read -r -d '' file; do

      [[ "$file" == "$keep" ]] && continue

      if [[ "$(basename "$file")" =~ \[([A-Za-z0-9_-]{11})\]\.mp3$ ]] &&
         [[ "${BASH_REMATCH[1]}" == "$id" ]]; then

        file_time=$(stat -c '%y' -- "$file")
        file_size=$(stat -c '%s' -- "$file")

        echo ""
        echo "DELETE (newer):"
        echo "  $(basename "$file")"
        echo "  Date: $file_time"
        echo "  Size: $file_size bytes"

        if [[ "$DELETE_DUPLICATES" == true ]]; then

          rm -f -- "$file"

          if [[ ! -e "$file" ]]; then
            echo "  >>> DELETED"
            removed=$((removed + 1))
          else
            echo "  >>> ERROR: could not delete file"
          fi

        else

          echo "  >>> DRY RUN — NOT DELETED"

        fi

      fi

    done < <(
      find "$OUTPUT_DIR" \
        -maxdepth 1 \
        -type f \
        -name '*.mp3' \
        -print0
    )

  done

  echo ""
  echo "===================================="
  echo "Duplicate files found: $total"

  if [[ "$DELETE_DUPLICATES" == true ]]; then
    echo "Duplicate files deleted: $removed"
  else
    echo "DRY RUN ONLY — no duplicate files were deleted."
  fi

  echo "===================================="
  echo ""
}

# ============================================================
# Cleanup interrupted yt-dlp process
# ============================================================

cleanup() {
  echo ""
  echo "Interrupt received — stopping yt-dlp cleanly..."

  if [[ -n "$CURRENT_PGID" ]]; then

    echo "Killing process group: $CURRENT_PGID"

    kill -TERM -- "-$CURRENT_PGID" 2>/dev/null || true

    sleep 1

    kill -KILL -- "-$CURRENT_PGID" 2>/dev/null || true

  fi

  exit 130
}

trap cleanup INT TERM

# ============================================================
# Parse arguments
# ============================================================

while [[ $# -gt 0 ]]; do

  case "$1" in

    -a|--audio)

      if [[ -n "$MODE" ]]; then
        echo "Error: only one mode may be specified."
        usage
        exit 1
      fi

      MODE="audio"
      shift
      ;;

    -v|--video)

      if [[ -n "$MODE" ]]; then
        echo "Error: only one mode may be specified."
        usage
        exit 1
      fi

      MODE="video"
      shift
      ;;

    -d|--delete)

      DELETE_DUPLICATES=true
      shift
      ;;

    -h|--help)

      usage
      exit 0
      ;;

    -*)

      echo "Unknown option: $1"
      usage
      exit 1
      ;;

    *)

      if [[ -z "$PLAYLIST_URL" ]]; then
        PLAYLIST_URL="$1"
      else
        echo "Unexpected argument: $1"
        usage
        exit 1
      fi

      shift
      ;;

  esac

done

# ============================================================
# Validate arguments
# ============================================================

if [[ -z "$PLAYLIST_URL" ]]; then
  echo "Error: playlist or video URL is required."
  usage
  exit 1
fi

# --delete by itself is valid.
#
#   yt_dl.sh --delete URL
#
# performs duplicate cleanup and exits.
#
# If combined with --audio or --video:
#
#   yt_dl.sh --delete --audio URL
#   yt_dl.sh --delete --video URL
#
# it cleans duplicates first, then downloads.

if [[ -z "$MODE" ]]; then

  if [[ "$DELETE_DUPLICATES" == true ]]; then
    MODE="delete"
  else
    echo "Error: you must specify either --audio or --video."
    usage
    exit 1
  fi

fi

# ============================================================
# DELETE-ONLY MODE
# ============================================================

if [[ "$MODE" == "delete" ]]; then

  cleanup_duplicates

  exit 0

fi

# ============================================================
# Check dependencies
# ============================================================

if [[ ! -f "$COOKIES_FILE" ]]; then
  echo "Cookies file not found: $COOKIES_FILE"
  exit 1
fi

if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "Error: yt-dlp not found."
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe not found."
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg not found."
  exit 1
fi

echo "yt-dlp version: $(yt-dlp --version)"

# ============================================================
# Setup
# ============================================================

mkdir -p "$OUTPUT_DIR"

ARCHIVE_FILE="$OUTPUT_DIR/.downloaded-${MODE}.txt"

touch "$ARCHIVE_FILE"

echo "Mode: $MODE"
echo "URL: $PLAYLIST_URL"
echo "Archive: $ARCHIVE_FILE"

# ============================================================
# Clean duplicates BEFORE downloading.
#
# Without --delete:
#   DRY RUN.
#
# With --delete:
#   Actually deletes newer duplicate MP3s.
# ============================================================

cleanup_duplicates

# ============================================================
# Get video IDs
#
# --flat-playlist works for:
#
#   single video
#   playlist
#
# ============================================================

echo "Fetching video IDs..."

IDS=$(yt-dlp \
  --cookies "$COOKIES_FILE" \
  --flat-playlist \
  --print "%(id)s" \
  --skip-download \
  "$PLAYLIST_URL" 2>&1)

FETCH_STATUS=$?

if [[ "$FETCH_STATUS" -ne 0 ]]; then
  echo "$IDS"
  echo "Failed to fetch video/playlist."
  exit 1
fi

# Remove blank lines.

IDS=$(printf '%s\n' "$IDS" | sed '/^[[:space:]]*$/d')

if [[ -z "$IDS" ]]; then
  echo "No videos found."
  exit 1
fi

VIDEO_COUNT=$(printf '%s\n' "$IDS" | wc -l)

echo "Videos found: $VIDEO_COUNT"

# ============================================================
# Main download loop
# ============================================================

while IFS= read -r ID; do

  [[ -z "$ID" ]] && continue

  echo ""
  echo "===================================="
  echo "Processing: $ID"
  echo "===================================="

  FILE=""

  # ==========================================================
  # Check archive FIRST.
  #
  # IMPORTANT:
  # Even if the archive contains the ID, we verify the actual
  # file using exact ID matching.
  # ==========================================================

  if grep -qxF "$ID" "$ARCHIVE_FILE"; then

    echo "ID is already in archive."

    if [[ "$MODE" == "audio" ]]; then

      FILE=$(find_audio_file "$ID" || true)

    else

      FILE=$(find_video_file "$ID" || true)

    fi

    # Archive says downloaded but exact file does not exist.
    # Remove stale archive entry so it gets downloaded again.

    if [[ -z "$FILE" ]]; then

      echo "Archive entry exists but matching output file is missing."
      echo "Removing stale archive entry."

      sed -i "\|^${ID}$|d" "$ARCHIVE_FILE"

    fi

  fi

  # ==========================================================
  # Find existing output file.
  #
  # IMPORTANT:
  # Exact YouTube ID matching is used.
  #
  # NO find -name "*[$ID].*"
  # ==========================================================

  if [[ -z "$FILE" ]]; then

    if [[ "$MODE" == "audio" ]]; then

      FILE=$(find_audio_file "$ID" || true)

    else

      FILE=$(find_video_file "$ID" || true)

    fi

  fi

  # ==========================================================
  # Validate existing file
  # ==========================================================

  if [[ -n "$FILE" ]] && [[ -f "$FILE" ]]; then

    echo "Existing file found:"
    echo "  $(basename "$FILE")"

    if [[ "$MODE" == "audio" ]]; then

      AUDIO_STREAMS=$(ffprobe \
        -v error \
        -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null | wc -l)

      if (( AUDIO_STREAMS > 0 )); then

        echo "OK: valid audio file."

        grep -qxF "$ID" "$ARCHIVE_FILE" || \
          echo "$ID" >> "$ARCHIVE_FILE"

        continue

      fi

    else

      VIDEO_STREAMS=$(ffprobe \
        -v error \
        -select_streams v \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null | wc -l)

      AUDIO_STREAMS=$(ffprobe \
        -v error \
        -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null | wc -l)

      if (( VIDEO_STREAMS > 0 )) &&
         (( AUDIO_STREAMS > 0 )); then

        echo "OK: valid video + audio file."

        grep -qxF "$ID" "$ARCHIVE_FILE" || \
          echo "$ID" >> "$ARCHIVE_FILE"

        continue

      fi

    fi

    echo "Invalid/incomplete file."
    echo "Deleting: $(basename "$FILE")"

    rm -f -- "$FILE"

    # Remove stale archive entry.

    sed -i "\|^${ID}$|d" "$ARCHIVE_FILE"

  else

    echo "No existing matching file."

  fi

  # ============================================================
  # Download
  # ============================================================

  if [[ "$MODE" == "audio" ]]; then

    echo "Downloading audio: $ID"

    setsid yt-dlp \
      --cookies "$COOKIES_FILE" \
      --no-playlist \
      -f "bestaudio/best" \
      -x \
      --audio-format mp3 \
      --no-overwrites \
      --retries 10 \
      --fragment-retries 10 \
      --retry-sleep 5 \
      --restrict-filenames \
      -o "$OUTPUT_DIR/%(title).200B [%(id)s].%(ext)s" \
      "https://www.youtube.com/watch?v=$ID" &

  else

    echo "Downloading video + audio: $ID"

    setsid yt-dlp \
      --cookies "$COOKIES_FILE" \
      --no-playlist \
      -f "bestvideo*+bestaudio/best" \
      --merge-output-format mp4 \
      --no-overwrites \
      --retries 10 \
      --fragment-retries 10 \
      --retry-sleep 5 \
      --restrict-filenames \
      -o "$OUTPUT_DIR/%(title).200B [%(id)s].%(ext)s" \
      "https://www.youtube.com/watch?v=$ID" &

  fi

  PID=$!

  # Get process group.

  CURRENT_PGID=$(ps -o pgid= "$PID" | tr -d ' ')

  wait "$PID"
  DOWNLOAD_STATUS=$?

  CURRENT_PGID=""

  if [[ "$DOWNLOAD_STATUS" -ne 0 ]]; then

    echo "Download failed: $ID"
    continue

  fi

  # ==========================================================
  # Find downloaded file.
  #
  # Exact ID matching only.
  # ==========================================================

  FILE=""

  if [[ "$MODE" == "audio" ]]; then

    FILE=$(find_audio_file "$ID" || true)

  else

    FILE=$(find_video_file "$ID" || true)

  fi

  # ==========================================================
  # Validate downloaded file
  # ==========================================================

  if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]]; then

    echo "ERROR: no output file generated."
    echo "Video ID: $ID"

    continue

  fi

  echo "Downloaded:"
  echo "  $(basename "$FILE")"

  # ==========================================================
  # Validate audio
  # ==========================================================

  if [[ "$MODE" == "audio" ]]; then

    AUDIO_STREAMS=$(ffprobe \
      -v error \
      -select_streams a \
      -show_entries stream=index \
      -of csv=p=0 \
      "$FILE" 2>/dev/null | wc -l)

    if (( AUDIO_STREAMS > 0 )); then

      grep -qxF "$ID" "$ARCHIVE_FILE" || \
        echo "$ID" >> "$ARCHIVE_FILE"

      echo "OK → audio validated → archived"

    else

      echo "ERROR → downloaded file contains no audio."
      echo "Deleting: $(basename "$FILE")"

      rm -f -- "$FILE"

    fi

  # ==========================================================
  # Validate video + audio
  # ==========================================================

  else

    VIDEO_STREAMS=$(ffprobe \
      -v error \
      -select_streams v \
      -show_entries stream=index \
      -of csv=p=0 \
      "$FILE" 2>/dev/null | wc -l)

    AUDIO_STREAMS=$(ffprobe \
      -v error \
      -select_streams a \
      -show_entries stream=index \
      -of csv=p=0 \
      "$FILE" 2>/dev/null | wc -l)

    if (( VIDEO_STREAMS > 0 )) &&
       (( AUDIO_STREAMS > 0 )); then

      grep -qxF "$ID" "$ARCHIVE_FILE" || \
        echo "$ID" >> "$ARCHIVE_FILE"

      echo "OK → video + audio validated → archived"

    else

      echo "ERROR → downloaded file does not contain both streams."
      echo "Video streams: $VIDEO_STREAMS"
      echo "Audio streams: $AUDIO_STREAMS"
      echo "Deleting: $(basename "$FILE")"

      rm -f -- "$FILE"

    fi

  fi

done <<< "$IDS"

# ============================================================
# Final duplicate cleanup
#
# If --delete was specified, remove duplicates created/found
# during this run too.
# ============================================================

if [[ "$DELETE_DUPLICATES" == true ]]; then

  echo ""
  echo "Running final duplicate cleanup..."

  cleanup_duplicates

fi

echo ""
echo "===================================="
echo "Finished."
echo "===================================="