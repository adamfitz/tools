#!/usr/bin/env bash

PLAYLIST_URL=""
OUTPUT_DIR="."
ARCHIVE_FILE=""
COOKIES_FILE="$HOME/cookies.txt"

MODE=""
CURRENT_PGID=""

usage() {
  echo "Usage: $0 [OPTIONS] <playlist_url>"
  echo ""
  echo "Options:"
  echo "  -a, --audio    Download audio only as MP3"
  echo "  -v, --video    Download video with audio"
  echo "  -h, --help     Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 --audio \"https://www.youtube.com/playlist?list=XXXX\""
  echo "  $0 --video \"https://www.youtube.com/playlist?list=XXXX\""
}

cleanup() {
  echo ""
  echo "Interrupt received — stopping yt-dlp cleanly..."

  if [ -n "$CURRENT_PGID" ]; then
    echo "Killing process group: $CURRENT_PGID"

    kill -TERM -- "-$CURRENT_PGID" 2>/dev/null
    sleep 1
    kill -KILL -- "-$CURRENT_PGID" 2>/dev/null
  fi

  exit 130
}

trap cleanup INT TERM

# ----------------------------
# Parse arguments
# ----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--audio)
      if [ -n "$MODE" ]; then
        echo "Error: only one mode may be specified."
        usage
        exit 1
      fi

      MODE="audio"
      shift
      ;;

    -v|--video)
      if [ -n "$MODE" ]; then
        echo "Error: only one mode may be specified."
        usage
        exit 1
      fi

      MODE="video"
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
      if [ -z "$PLAYLIST_URL" ]; then
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

# ----------------------------
# Validate arguments
# ----------------------------
if [ -z "$PLAYLIST_URL" ]; then
  echo "Error: playlist URL is required."
  usage
  exit 1
fi

if [ -z "$MODE" ]; then
  echo "Error: you must specify either --audio or --video."
  usage
  exit 1
fi

# ----------------------------
# Check cookies
# ----------------------------
if [ ! -f "$COOKIES_FILE" ]; then
  echo "Cookies file not found: $COOKIES_FILE"
  exit 1
fi

# ----------------------------
# Check yt-dlp
# ----------------------------
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "Error: yt-dlp not found or not in PATH."
  echo "Please install yt-dlp and ensure it is available in PATH."
  exit 1
fi

if ! yt-dlp --version >/dev/null 2>&1; then
  echo "Error: yt-dlp was found but could not be executed."
  exit 1
fi

echo "yt-dlp version: $(yt-dlp --version)"

# ----------------------------
# Check required dependencies
# ----------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq not found or not in PATH."
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe not found or not in PATH."
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg not found or not in PATH."
  echo "ffmpeg is required for video + audio downloads."
  exit 1
fi

# ----------------------------
# Setup
# ----------------------------
mkdir -p "$OUTPUT_DIR"

# Separate archives for audio and video.
ARCHIVE_FILE="$OUTPUT_DIR/.downloaded-${MODE}.txt"

touch "$ARCHIVE_FILE"

echo "Mode: $MODE"
echo "Playlist: $PLAYLIST_URL"
echo "Archive: $ARCHIVE_FILE"

# ----------------------------
# Fetch playlist IDs
# ----------------------------
echo "Fetching playlist..."

JSON=$(yt-dlp \
  --cookies "$COOKIES_FILE" \
  --flat-playlist \
  -J \
  "$PLAYLIST_URL" 2>/dev/null)

if [ -z "$JSON" ] || [ "$JSON" = "null" ]; then
  echo "Failed to fetch playlist."
  exit 1
fi

IDS=$(echo "$JSON" | jq -r '.entries[]?.id')

if [ -z "$IDS" ]; then
  echo "No videos found in playlist."
  exit 1
fi

# ----------------------------
# Main loop
# ----------------------------
for ID in $IDS; do

  echo "------------------------------------"
  echo "Processing: $ID"

  # ----------------------------
  # Find existing file
  # ----------------------------
  if [ "$MODE" = "audio" ]; then

    FILE=$(find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      -name "*[$ID].mp3" \
      -print -quit)

  else

    # Do not assume mp4/webm/mkv/etc.
    FILE=$(find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      -name "*[$ID].*" \
      ! -name "*.part" \
      ! -name "*.ytdl" \
      -print -quit)

  fi

  # ----------------------------
  # Check existing file
  # ----------------------------
  if [ -n "$FILE" ] && [ -f "$FILE" ]; then

    if [ "$MODE" = "audio" ]; then

      # Audio must contain an audio stream.
      AUDIO_STREAMS=$(ffprobe \
        -v error \
        -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null | wc -l)

      if [ "$AUDIO_STREAMS" -gt 0 ]; then
        echo "OK (audio file exists + valid): $ID"
        echo "File: $(basename "$FILE")"

        grep -qxF "$ID" "$ARCHIVE_FILE" || \
          echo "$ID" >> "$ARCHIVE_FILE"

        continue
      fi

    else

      # Video must contain BOTH video and audio streams.
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

      if [ "$VIDEO_STREAMS" -gt 0 ] && [ "$AUDIO_STREAMS" -gt 0 ]; then
        echo "OK (video + audio exists + valid): $ID"
        echo "File: $(basename "$FILE")"

        grep -qxF "$ID" "$ARCHIVE_FILE" || \
          echo "$ID" >> "$ARCHIVE_FILE"

        continue
      fi

    fi

    echo "Invalid/incomplete file detected → deleting: $ID"
    echo "File: $(basename "$FILE")"

    rm -f "$FILE"

  else
    echo "Missing file → downloading: $ID"
  fi

  # ----------------------------
  # Remove ID from archive
  # ----------------------------
  grep -vxF "$ID" "$ARCHIVE_FILE" > "$ARCHIVE_FILE.tmp" || true
  mv "$ARCHIVE_FILE.tmp" "$ARCHIVE_FILE"

  # ----------------------------
  # Download
  # ----------------------------
  if [ "$MODE" = "audio" ]; then

    echo "Downloading audio: $ID"

    setsid yt-dlp \
      --cookies "$COOKIES_FILE" \
      -f "bestaudio" \
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

    # Best video + best audio.
    #
    # No forced container.
    # yt-dlp/ffmpeg chooses the appropriate container
    # for the selected streams.
    setsid yt-dlp \
      --cookies "$COOKIES_FILE" \
      -f "bestvideo*+bestaudio/best" \
      --no-overwrites \
      --retries 10 \
      --fragment-retries 10 \
      --retry-sleep 5 \
      --restrict-filenames \
      -o "$OUTPUT_DIR/%(title).200B [%(id)s].%(ext)s" \
      "https://www.youtube.com/watch?v=$ID" &

  fi

  # ----------------------------
  # Track yt-dlp process group
  # ----------------------------
  PID=$!

  CURRENT_PGID=$(ps -o pgid= "$PID" | tr -d ' ')

  wait "$PID"
  DOWNLOAD_STATUS=$?

  CURRENT_PGID=""

  if [ "$DOWNLOAD_STATUS" -ne 0 ]; then
    echo "Download failed: $ID"
    continue
  fi

  # ----------------------------
  # Find downloaded file
  # ----------------------------
  if [ "$MODE" = "audio" ]; then

    FILE=$(find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      -name "*[$ID].mp3" \
      -print -quit)

  else

    FILE=$(find "$OUTPUT_DIR" \
      -maxdepth 1 \
      -type f \
      -name "*[$ID].*" \
      ! -name "*.part" \
      ! -name "*.ytdl" \
      -print -quit)

  fi

  # ----------------------------
  # Validate downloaded file
  # ----------------------------
  if [ -n "$FILE" ] && [ -f "$FILE" ]; then

    if [ "$MODE" = "audio" ]; then

      AUDIO_STREAMS=$(ffprobe \
        -v error \
        -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 \
        "$FILE" 2>/dev/null | wc -l)

      if [ "$AUDIO_STREAMS" -gt 0 ]; then

        grep -qxF "$ID" "$ARCHIVE_FILE" || \
          echo "$ID" >> "$ARCHIVE_FILE"

        echo "OK → audio validated → archived"
        echo "File: $(basename "$FILE")"

      else

        echo "ERROR → downloaded file contains no audio"
        echo "Deleting: $(basename "$FILE")"

        rm -f "$FILE"

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

      if [ "$VIDEO_STREAMS" -gt 0 ] && [ "$AUDIO_STREAMS" -gt 0 ]; then

        grep -qxF "$ID" "$ARCHIVE_FILE" || \
          echo "$ID" >> "$ARCHIVE_FILE"

        echo "OK → video + audio validated → archived"
        echo "File: $(basename "$FILE")"

      else

        echo "ERROR → downloaded file does not contain both video and audio"
        echo "Video streams: $VIDEO_STREAMS"
        echo "Audio streams: $AUDIO_STREAMS"
        echo "Deleting: $(basename "$FILE")"

        rm -f "$FILE"

      fi

    fi

  else
    echo "No output file generated: $ID"
  fi

done

echo "------------------------------------"
echo "Finished."