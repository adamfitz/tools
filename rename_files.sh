#!/bin/bash

# Iterate over all files in the current directory

for og_filename in *; do

    # Only process regular files
    [ -f "$og_filename" ] || continue

    # Never process this script
    [ "$og_filename" = "rename_file.sh" ] && continue

    # Only process CBZ files
    case "$og_filename" in
        *.cbz) ;;
        *) continue ;;
    esac

    # Extract chapter number, including fractional chapters
    chapter=$(echo "$og_filename" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)

    # Skip files where no chapter number was found
    [ -n "$chapter" ] || continue

    # Create new filename
    if [[ "$chapter" == *.* ]]; then
        integer_part=${chapter%%.*}
        decimal_part=${chapter#*.}
        new_filename=$(printf "ch%03d.%s.cbz" "$integer_part" "$decimal_part")
    else
        new_filename=$(printf "ch%03d.cbz" "$chapter")
    fi

    # Don't rename if the filename is already correct
    [ "$og_filename" = "$new_filename" ] && continue

    # Show what will happen
    echo "Renaming: $og_filename -> $new_filename"

    # Perform rename
    mv -- "$og_filename" "$new_filename"

done