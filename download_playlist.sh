#!/usr/bin/env bash

PLAYLIST_URL="$1"
OUTPUT_DIR="."
ARCHIVE_FILE="$OUTPUT_DIR/.downloaded.txt"

CURRENT_PGID=""

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

if [ -z "$PLAYLIST_URL" ]; then
  echo "Usage: $0 <playlist_url>"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ----------------------------
# Fetch playlist IDs
# ----------------------------
JSON=$(yt-dlp --flat-playlist -J "$PLAYLIST_URL" 2>/dev/null)

if [ -z "$JSON" ] || [ "$JSON" = "null" ]; then
  echo "Failed to fetch playlist"
  exit 1
fi

IDS=$(echo "$JSON" | jq -r '.entries[]?.id')

# ----------------------------
# Main loop
# ----------------------------
for ID in $IDS; do

  echo "------------------------------------"
  echo "Processing: $ID"

  FILE=$(ls "$OUTPUT_DIR"/*"[$ID].mp3" 2>/dev/null | head -n 1)

  NEEDS_DOWNLOAD=0

  # ----------------------------
  # SELF-HEALING LOGIC (FIXED)
  # ----------------------------

  if [ -f "$FILE" ]; then
    ffprobe -v error "$FILE" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
      echo "OK (file exists + valid): $ID"

      # ensure archive consistency
      grep -q "$ID" "$ARCHIVE_FILE" 2>/dev/null || echo "$ID" >> "$ARCHIVE_FILE"
      continue
    else
      echo "Corrupt file detected → re-downloading: $ID"
      rm -f "$FILE"
      grep -v "$ID" "$ARCHIVE_FILE" > "$ARCHIVE_FILE.tmp" 2>/dev/null && mv "$ARCHIVE_FILE.tmp" "$ARCHIVE_FILE"
      NEEDS_DOWNLOAD=1
    fi

  else
    echo "Missing file → re-downloading: $ID"
    grep -v "$ID" "$ARCHIVE_FILE" > "$ARCHIVE_FILE.tmp" 2>/dev/null && mv "$ARCHIVE_FILE.tmp" "$ARCHIVE_FILE"
    NEEDS_DOWNLOAD=1
  fi

  # ----------------------------
  # Download if needed
  # ----------------------------
  if [ "$NEEDS_DOWNLOAD" -eq 1 ]; then

    echo "Downloading: $ID"

    setsid yt-dlp \
      -f "ba" \
      -x \
      --audio-format mp3 \
      --no-overwrites \
      --retries 10 \
      --fragment-retries 10 \
      --retry-sleep 5 \
      --restrict-filenames \
      -o "$OUTPUT_DIR/%(title).200B [%(id)s].%(ext)s" \
      "https://www.youtube.com/watch?v=$ID" &

    PID=$!
    CURRENT_PGID=$(ps -o pgid= "$PID" | tr -d ' ')

    wait "$PID"
    CURRENT_PGID=""

    FILE=$(ls "$OUTPUT_DIR"/*"[$ID].mp3" 2>/dev/null | head -n 1)

    if [ -f "$FILE" ]; then
      ffprobe -v error "$FILE" >/dev/null 2>&1

      if [ $? -eq 0 ]; then
        echo "$ID" >> "$ARCHIVE_FILE"
        echo "OK → archived"
      else
        echo "Corrupt after download → deleting"
        rm -f "$FILE"
      fi
    else
      echo "No output file generated: $ID"
    fi
  fi

done

