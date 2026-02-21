#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="$1"
OUTPUT_DIR="$2"

[[ -d "$INPUT_DIR" ]] || { echo "Input directory not found"; exit 1; }

mkdir -p "$OUTPUT_DIR"
shopt -s nullglob

# Clean leftover temp files from previous crashes
find "$OUTPUT_DIR" -name "*.tmp.mp3" -delete

is_valid_mp3() {
    ffprobe -v error "$1" >/dev/null 2>&1
}

for file in "$INPUT_DIR"/*.webm "$INPUT_DIR"/*.mkv; do
    base="$(basename "${file%.*}")"
    output="$OUTPUT_DIR/$base.mp3"
    tmp="$OUTPUT_DIR/$base.tmp.mp3"

    # If completed file exists and valid → skip
    if [[ -f "$output" ]]; then
        if is_valid_mp3 "$output"; then
            echo "Skipping (complete): $output"
            continue
        else
            echo "Removing broken file: $output"
            rm -f "$output"
        fi
    fi

    echo "Converting: $file → $output"

    rm -f "$tmp"

    if ffmpeg -y -i "$file" -vn -q:a 2 "$tmp"; then
        mv "$tmp" "$output"
        echo "Completed: $output"
    else
        echo "Failed: $file"
        rm -f "$tmp"
    fi
done

echo "Done."