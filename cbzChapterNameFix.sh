#!/bin/bash
# cbzChapterNameFix.sh
# Rename CBZ files like "10 (eng).cbz" → "ch010.cbz" safely.
#
# Features:
# - Dry run by default
# - --apply to perform changes
# - --dir / -d target directory
# - Handles leading zero numbers safely
# - Collision-safe renaming
# - Auto-recovers interrupted runs (.tmp files)
#
# Usage:
#   cbzChapterNameFix.sh
#   cbzChapterNameFix.sh --dir "/path"
#   cbzChapterNameFix.sh --apply --dir "/path"

DRY_RUN=true
TARGET_DIR=""

# ----------------------------
# Parse arguments
# ----------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            DRY_RUN=false
            shift
            ;;
        --dir|-d)
            TARGET_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--apply] [--dir PATH]"
            exit 1
            ;;
    esac
done

TARGET_DIR="${TARGET_DIR:-$(pwd)}"

echo "Processing CBZ files in: $TARGET_DIR"

if $DRY_RUN; then
    echo "Running in DRY RUN mode (no files will be renamed)"
    echo "Use --apply to perform changes"
else
    echo "Applying changes (files WILL be renamed)"
fi

cd "$TARGET_DIR" || { echo "Directory not found: $TARGET_DIR"; exit 1; }

shopt -s nullglob

# ==========================================================
# ⭐ AUTO-RECOVER INTERRUPTED RUNS FIRST
# ==========================================================
tmpfiles=( ch*.cbz.tmp )

if [ ${#tmpfiles[@]} -gt 0 ]; then
    echo
    echo "Detected interrupted run — attempting recovery..."

    for tmpf in "${tmpfiles[@]}"; do
        target="${tmpf%.tmp}"

        if [[ -e "$target" ]]; then
            echo "Recovery skipped: $target already exists (keeping $tmpf)"
            continue
        fi

        if $DRY_RUN; then
            echo "[DRY RUN][RECOVER] $tmpf → $target"
        else
            echo "Recovering $tmpf → $target"
            mv -- "$tmpf" "$target"
        fi
    done

    echo
fi

# ==========================================================
# Read all CBZ filenames into array BEFORE renaming
# ==========================================================
files=( *.cbz )

if [ ${#files[@]} -eq 0 ]; then
    echo "No CBZ files found in $TARGET_DIR"
    exit 0
fi

# ==========================================================
# Rename files
# ==========================================================
for f in "${files[@]}"; do
    # Skip already-correct files
    if [[ "$f" =~ ^ch[0-9]{3}\.cbz$ ]]; then
        echo "Skipping already renamed file: $f"
        continue
    fi

    # Extract leading number
    if [[ "$f" =~ ^([0-9]+) ]]; then
        num="${BASH_REMATCH[1]}"

        # Force base-10 so 008/009 don't break
        printf -v new "ch%03d.cbz" "$((10#$num))"

        if [[ "$f" == "$new" ]]; then
            continue
        fi

        if [[ -e "$new" ]]; then
            tmp="${new}.tmp"
            echo "Target exists: $new → staging $f → $tmp"

            if ! $DRY_RUN; then
                mv -- "$f" "$tmp"
            fi
        else
            if $DRY_RUN; then
                echo "[DRY RUN] $f → $new"
            else
                mv -- "$f" "$new"
            fi
        fi
    else
        echo "Skipping $f: no leading number found"
    fi
done

# ==========================================================
# Finalize staged files
# ==========================================================
tmpfiles=( ch*.cbz.tmp )

if [ ${#tmpfiles[@]} -gt 0 ]; then
    echo
    echo "Finalizing staged files..."

    for tmpf in "${tmpfiles[@]}"; do
        target="${tmpf%.tmp}"

        if [[ -e "$target" ]]; then
            echo "Finalize skipped: $target already exists (keeping $tmpf)"
            continue
        fi

        if $DRY_RUN; then
            echo "[DRY RUN] $tmpf → $target"
        else
            echo "Renaming $tmpf → $target"
            mv -- "$tmpf" "$target"
        fi
    done
fi

echo
echo "Done."
