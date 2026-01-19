#!/bin/bash
# cbzChapterNameFix.sh
# Rename CBZ files like "10 (eng).cbz" → "ch010.cbz" safely.
# Usage: cbzChapterNameFix.sh [directory]

TARGET_DIR="${1:-$(pwd)}"
echo "Processing CBZ files in: $TARGET_DIR"

cd "$TARGET_DIR" || { echo "Directory not found: $TARGET_DIR"; exit 1; }

# Read all CBZ filenames into an array BEFORE any renaming
mapfile -t files < <(ls *.cbz 2>/dev/null)

if [ ${#files[@]} -eq 0 ]; then
    echo "No CBZ files found in $TARGET_DIR"
    exit 0
fi

for f in "${files[@]}"; do
    # Skip files that already match the chXXX.cbz format
    if [[ "$f" =~ ^ch[0-9]{3}\.cbz$ ]]; then
        echo "Skipping already renamed file: $f"
        continue
    fi

    # Extract the leading number
    if [[ "$f" =~ ^([0-9]+) ]]; then
        num="${BASH_REMATCH[1]}"
        # Create the new zero-padded filename
        printf -v new "ch%03d.cbz" "$num"

        if [[ -e "$new" ]]; then
            # If the target exists, rename to a temporary name first
            tmp="${new}.tmp"
            echo "Warning: $new exists, moving $f to $tmp"
            mv -i -- "$f" "$tmp"
        else
            mv -i -- "$f" "$new"
        fi
    else
        echo "Skipping $f: no leading number found"
    fi
done

# Now rename any temporary files to their intended names
for tmpf in *.tmp; do
    target="${tmpf%.tmp}"
    echo "Renaming $tmpf → $target"
    mv -i -- "$tmpf" "$target"
done

