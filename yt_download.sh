```bash
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
  echo "Usage: $0 [OPTIONS] [<playlist_or_video_url>]"
  echo ""
  echo "Options:"
  echo "  -a, --audio    Download audio only as MP3"
  echo "  -v, --video    Download video with audio"
  echo "  -d, --delete   Delete newer duplicate files, keeping the oldest copy"
  echo "  -h, --help     Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 --audio \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --video \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --audio \"https://www.youtube.com/watch?v=XXXX\""
  echo "  $0 --video \"https://www.youtube.com/watch?v=XXXX\""
  echo "  $0 --delete"
  echo "  $0 --delete \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --audio --delete \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --video --delete \"https://www.youtube.com/playlist?list=XXXX\""
}

# ============================================================
# Determine media type from filename extension.
#
# Audio and video are deliberately deduplicated separately.
#
# Example:
#
#   title [ABC123xyz01].mp3  -> audio
#   title [ABC123xyz01].m4a  -> audio
#   title [ABC123xyz01].mp4  -> video
#   title [ABC123xyz01].mkv  -> video
#
# MP3 and MP4 with the same YouTube ID are NOT duplicates.
# ============================================================

get_media_type() {
  local file="$1"
  local ext

  ext="${file##*.}"
  ext="${ext,,}"

  case "$ext" in
    mp3|m4a|aac|opus|ogg|oga|wav|flac|alac|wma)
      echo "audio"
      ;;

    mp4|mkv|webm|avi|mov|m4v|wmv|flv|ts|m2ts|mts|3gp)
      echo "video"
      ;;

    *)
      echo "unknown"
      ;;
  esac
}

# ============================================================
# Extract a YouTube ID from the end of a filename.
#
# Expected:
#
#   Anything [ABC123xyz01].mp3
#   Anything [ABC123xyz01].mp4
#
# YouTube IDs are exactly 11 characters and contain:
#
#   A-Z
#   a-z
#   0-9
#   -
#   _
# ============================================================

get_youtube_id() {
  local file
  file="$(basename "$1")"

  if [[ "$file" =~ \[([A-Za-z0-9_-]{11})\]\.[^.]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

# ============================================================
# Duplicate cleanup
#
# Audio is deduplicated independently from video.
#
# Same ID + same media type:
#
#   oldest = KEEP
#   newer  = DELETE
#
# Same ID + different media type:
#
#   MP3 and MP4 are BOTH KEPT
# ============================================================

cleanup_duplicates() {
  echo ""
  echo "===================================="
  echo "Checking for duplicate audio/video files"
  echo "Directory: $OUTPUT_DIR"
  echo "===================================="

  declare -A oldest_file
  declare -A oldest_time
  declare -A duplicate_count

  local file
  local id
  local media_type
  local key
  local mtime

  while IFS= read -r -d '' file; do

    id=""

    if ! id="$(get_youtube_id "$file")"; then
      continue
    fi

    media_type="$(get_media_type "$file")"

    if [[ "$media_type" == "unknown" ]]; then
      continue
    fi

    # Separate namespace for audio/video.
    #
    # This means:
    #
    #   audio:ABC123xyz01
    #   video:ABC123xyz01
    #
    # are completely independent.
    key="${media_type}:${id}"

    mtime="$(stat -c '%Y' -- "$file")"

    if [[ -z "${oldest_file[$key]+x}" ]]; then

      oldest_file["$key"]="$file"
      oldest_time["$key"]="$mtime"
      duplicate_count["$key"]=1

    else

      duplicate_count["$key"]=$((duplicate_count["$key"] + 1))

      if (( mtime < oldest_time["$key"] )); then
        oldest_file["$key"]="$file"
        oldest_time["$key"]="$mtime"
      fi

    fi

  done < <(
    find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      -print0
  )

  local total_duplicates=0
  local total_deleted=0

  local count
  local keep
  local file_time
  local file_size
  local label

  for key in "${!duplicate_count[@]}"; do

    count="${duplicate_count[$key]}"

    (( count > 1 )) || continue

    total_duplicates=$((total_duplicates + count - 1))

    keep="${oldest_file[$key]}"

    if [[ "$key" == audio:* ]]; then
      label="AUDIO"
    else
      label="VIDEO"
    fi

    id="${key#*:}"

    echo ""
    echo "------------------------------------"
    echo "$label duplicate: $id"
    echo "------------------------------------"

    echo "KEEP (oldest):"
    echo "  $(basename "$keep")"
    echo "  Date: $(stat -c '%y' -- "$keep")"
    echo "  Size: $(stat -c '%s' -- "$keep") bytes"

    while IFS= read -r -d '' file; do

      [[ "$file" == "$keep" ]] && continue

      local other_id
      local other_type

      other_id=""

      if ! other_id="$(get_youtube_id "$file")"; then
        continue
      fi

      [[ "$other_id" == "$id" ]] || continue

      other_type="$(get_media_type "$file")"

      [[ "$other_type" == "$media_type" ]] || continue

      file_time="$(stat -c '%y' -- "$file")"
      file_size="$(stat -c '%s' -- "$file")"

      echo ""
      echo "DELETE (newer):"
      echo "  $(basename "$file")"
      echo "  Date: $file_time"
      echo "  Size: $file_size bytes"

      if [[ "$DELETE_DUPLICATES" == true ]]; then

        if rm -f -- "$file"; then

          if [[ ! -e "$file" ]]; then
            echo "  >>> DELETED"
            total_deleted=$((total_deleted + 1))
          else
            echo "  >>> ERROR: file still exists"
          fi

        else

          echo "  >>> ERROR: failed to delete"

        fi

      else

        echo "  >>> DRY RUN — NOT DELETED"

      fi

    done < <(
      find "$OUTPUT_DIR" \
        -maxdepth 1 \
        -type f \
        -print0
    )

  done

  echo ""
  echo "===================================="
  echo "Duplicate scan complete"
  echo "===================================="
  echo "Duplicate files found: $total_duplicates"

  if [[ "$DELETE_DUPLICATES" == true ]]; then
    echo "Duplicate files deleted: $total_deleted"
  else
    echo "DRY RUN ONLY — no files were deleted."
  fi

  echo "===================================="
  echo ""
}

# ============================================================
# Cleanup interrupted yt-dlp
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
# Validate mode
# ============================================================

# --delete by itself is a valid standalone operation.
#
#   yt_dl.sh --delete
#
# No URL is needed.
#
# --audio and --video still require a URL.
# ============================================================

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
#
# No network access.
# No URL.
# No yt-dlp.
# No cookies.
# No ffmpeg.
# No ffprobe.
# ============================================================

if [[ "$MODE" == "delete" ]]; then

  if [[ $# -gt 0 ]]; then
    :
  fi

  cleanup_duplicates

  exit 0
fi

# ============================================================
# Audio/video modes require URL
# ============================================================

if [[ -z "$PLAYLIST_URL" ]]; then

  echo "Error: playlist or video URL is required for --audio/--video."
  usage
  exit 1

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
# Optional duplicate cleanup before downloading.
# ============================================================

cleanup_duplicates

# ============================================================
# Fetch IDs
#
# Works with both:
#
#   single video
#   playlist
# ============================================================

echo "Fetching video IDs..."

IDS=$(
  yt-dlp \
    --cookies "$COOKIES_FILE" \
    --flat-playlist \
    --print "%(id)s" \
    --skip-download \
    "$PLAYLIST_URL"
)

FETCH_STATUS=$?

if [[ "$FETCH_STATUS" -ne 0 ]]; then
  echo "Failed to fetch video/playlist."
  exit 1
fi

IDS="$(printf '%s\n' "$IDS" | sed '/^[[:space:]]*$/d')"

if [[ -z "$IDS" ]]; then
  echo "No videos found."
  exit 1
fi

VIDEO_COUNT="$(printf '%s\n' "$IDS" | wc -l)"

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
  # Find existing file
  #
  # Escape the literal [ and ] by using a character class:
  #
  #   *[[]ID].mp3
  #
  # This avoids treating [ID] as a shell/find wildcard.
  # ==========================================================

  if [[ "$MODE" == "audio" ]]; then

    FILE="$(
      find "$OUTPUT_DIR" \
        -maxdepth 1 \
        -type f \
        -name "*[[]${ID}].mp3" \
        -print -quit
    )"

  else

    FILE="$(
      find "$OUTPUT_DIR" \
        -maxdepth 1 \
        -type f \
        \( \
          -name "*[[]${ID}].mp4" \
          -o -name "*[[]${ID}].mkv" \
          -o -name "*[[]${ID}].webm" \
          -o -name "*[[]${ID}].m4v" \
          -o -name "*[[]${ID}].mov" \
          -o -name "*[[]${ID}].avi" \
          -o -name "*[[]${ID}].ts" \
        \) \
        ! -name "*.part" \
        ! -name "*.ytdl" \
        -print -quit
    )"

  fi

  # ==========================================================
  # Validate existing file
  # ==========================================================

  if [[ -n "$FILE" ]] && [[ -f "$FILE" ]]; then

    echo "Existing file found:"
    echo "  $(basename "$FILE")"

    if [[ "$MODE" == "audio" ]]; then

      AUDIO_STREAMS="$(
        ffprobe \
          -v error \
          -select_streams a \
          -show_entries stream=index \
          -of csv=p=0 \
          "$FILE" 2>/dev/null |
          wc -l
      )"

      if (( AUDIO_STREAMS > 0 )); then

        echo "OK: valid audio file."

        grep -qxF "$ID" "$ARCHIVE_FILE" ||
          echo "$ID" >> "$ARCHIVE_FILE"

        continue

      fi

    else

      VIDEO_STREAMS="$(
        ffprobe \
          -v error \
          -select_streams v \
          -show_entries stream=index \
          -of csv=p=0 \
          "$FILE" 2>/dev/null |
          wc -l
      )"

      AUDIO_STREAMS="$(
        ffprobe \
          -v error \
          -select_streams a \
          -show_entries stream=index \
          -of csv=p=0 \
          "$FILE" 2>/dev/null |
          wc -l
      )"

      if (( VIDEO_STREAMS > 0 )) &&
         (( AUDIO_STREAMS > 0 )); then

        echo "OK: valid video + audio file."

        grep -qxF "$ID" "$ARCHIVE_FILE" ||
          echo "$ID" >> "$ARCHIVE_FILE"

        continue

      fi

    fi

    echo "Invalid/incomplete file."
    echo "Deleting: $(basename "$FILE")"

    rm -f -- "$FILE"

    sed -i "\|^${ID}$|d" "$ARCHIVE_FILE"

  else

    echo "No existing file."

  fi

  # ==========================================================
  # Download
  # ==========================================================

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

  CURRENT_PGID="$(ps -o pgid= "$PID" | tr -d ' ')"

  wait "$PID"

  DOWNLOAD_STATUS=$?

  CURRENT_PGID=""

  if [[ "$DOWNLOAD_STATUS" -ne 0 ]]; then

    echo "Download failed: $ID"
    continue

  fi

  # ==========================================================
  # Find downloaded file
  # ==========================================================

  FILE=""

  if [[ "$MODE" == "audio" ]]; then

    FILE="$(
      find "$OUTPUT_DIR" \
        -maxdepth 1 \
        -type f \
        -name "*[[]${ID}].mp3" \
        -print -quit
    )"

  else

    FILE="$(
      find "$OUTPUT_DIR" \
        -maxdepth 1 \
        -type f \
        \( \
          -name "*[[]${ID}].mp4" \
          -o -name "*[[]${ID}].mkv" \
          -o -name "*[[]${ID}].webm" \
          -o -name "*[[]${ID}].m4v" \
          -o -name "*[[]${ID}].mov" \
          -o -name "*[[]${ID}].avi" \
          -o -name "*[[]${ID}].ts" \
        \) \
        ! -name "*.part" \
        ! -name "*.ytdl" \
        -print -quit
    )"

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

  if [[ "$MODE" == "audio" ]]; then

    AUDIO_STREAMS="$(
      ffprobe \
        -v error \
        -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null |
        wc -l
    )"

    if (( AUDIO_STREAMS > 0 )); then

      grep -qxF "$ID" "$ARCHIVE_FILE" ||
        echo "$ID" >> "$ARCHIVE_FILE"

      echo "OK → audio validated → archived"

    else

      echo "ERROR → downloaded file contains no audio."
      echo "Deleting: $(basename "$FILE")"

      rm -f -- "$FILE"

    fi

  else

    VIDEO_STREAMS="$(
      ffprobe \
        -v error \
        -select_streams v \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null |
        wc -l
    )"

    AUDIO_STREAMS="$(
      ffprobe \
        -v error \
        -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null |
        wc -l
    )"

    if (( VIDEO_STREAMS > 0 )) &&
       (( AUDIO_STREAMS > 0 )); then

      grep -qxF "$ID" "$ARCHIVE_FILE" ||
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
# Final duplicate cleanup when --delete was supplied.
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
```
