#!/usr/bin/env bash

# cbzChapterNameFix.sh
#
# Rename CBZ files to canonical:
#   ch001.cbz
#   ch002.cbz
#   ch072.5.cbz
#   ch100.cbz
#
# Supported input formats include:
#   1.cbz
#   01.cbz
#   001.cbz
#   Chapter 1.cbz
#   Chapter 01.cbz
#   Chapter 001.cbz
#   chapter 100.cbz
#   Ch 100.cbz
#   Ch. 100.cbz
#   Ch.100.cbz
#   ch1.cbz
#   ch01.cbz
#   ch001.cbz
#   Chapter 72.5.cbz
#   72.5.cbz
#
# Also supports chapter prefixes after volume information:
#   Vol.01 Ch.0001.cbz
#   Vol.01 Ch.0001 - Title.cbz
#   Vol.02 Ch.0010.cbz
#   Vol.02 Ch.0010.5.cbz
#   Vol.03 Ch.0013 (en) [Group].cbz
#   Vol.03 Chapter 0014.cbz
#
# Features:
#   - Dry run by default
#   - --apply to perform changes
#   - --dir / -d target directory
#   - Handles leading zero numbers safely
#   - Handles fractional chapters
#   - Handles Ch / Ch. / Chapter prefixes anywhere in filename
#   - Correctly ignores volume numbers when an explicit chapter number exists
#   - Collision-safe renaming
#   - Reads all filenames before renaming
#   - Uses temporary staging for collisions
#   - Attempts to recover interrupted .tmp files
#
# Usage:
#   cbzChapterNameFix.sh
#   cbzChapterNameFix.sh --dir "/path"
#   cbzChapterNameFix.sh --apply --dir "/path"

set -u

DRY_RUN=true
TARGET_DIR=""

# ==========================================================
# Parse arguments
# ==========================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            DRY_RUN=false
            shift
            ;;

        --dir|-d)
            if [[ $# -lt 2 ]]; then
                echo "Error: --dir requires a directory"
                exit 1
            fi

            TARGET_DIR="$2"
            shift 2
            ;;

        --help|-h)
            cat <<EOF
Usage:
  $0 [--apply] [--dir PATH]

Options:
  --apply       Actually rename files
  --dir PATH    Directory containing CBZ files
  --help        Show this help

Default behaviour is DRY RUN.
EOF
            exit 0
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

cd "$TARGET_DIR" || {
    echo "Directory not found: $TARGET_DIR"
    exit 1
}

shopt -s nullglob

# ==========================================================
# Function: convert chapter number to canonical filename
#
# Examples:
#   1       -> ch001.cbz
#   01      -> ch001.cbz
#   001     -> ch001.cbz
#   12      -> ch012.cbz
#   100     -> ch100.cbz
#   72.5    -> ch072.5.cbz
#   0010.5  -> ch010.5.cbz
# ==========================================================

make_canonical_name() {
    local chapter="$1"
    local integer_part
    local fractional_part
    local integer_value
    local formatted

    # ------------------------------------------------------
    # Fractional chapter
    # ------------------------------------------------------

    if [[ "$chapter" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        integer_part="${BASH_REMATCH[1]}"
        fractional_part="${BASH_REMATCH[2]}"

        # Remove leading zeroes safely.
        integer_part="${integer_part#"${integer_part%%[!0]*}"}"

        # If it was all zeroes, use 0.
        [[ -z "$integer_part" ]] && integer_part="0"

        # Force decimal interpretation.
        integer_value=$((10#$integer_part))

        printf -v formatted "%03d.%s" "$integer_value" "$fractional_part"

        printf 'ch%s.cbz' "$formatted"
        return 0
    fi

    # ------------------------------------------------------
    # Integer chapter
    # ------------------------------------------------------

    if [[ "$chapter" =~ ^[0-9]+$ ]]; then

        # Remove leading zeroes.
        integer_part="${chapter#"${chapter%%[!0]*}"}"

        # If all zeroes, use 0.
        [[ -z "$integer_part" ]] && integer_part="0"

        # Force base 10.
        integer_value=$((10#$integer_part))

        printf -v formatted "%03d" "$integer_value"

        printf 'ch%s.cbz' "$formatted"
        return 0
    fi

    return 1
}

# ==========================================================
# Function: extract chapter number from filename
#
# IMPORTANT:
# Explicit Ch / Chapter prefixes are searched ANYWHERE
# in the filename.
#
# This means:
#
#   Ch.0001.cbz
#   Chapter 0001.cbz
#   Vol.01 Ch.0001.cbz
#   Vol.02 Ch.0010.5.cbz
#   Vol.03 Ch.0013 (en).cbz
#
# are all recognised correctly.
#
# Explicit chapter prefixes are checked BEFORE a leading
# number so that:
#
#   Vol.02 Ch.0010.cbz
#
# gets chapter 0010, NOT volume 02.
# ==========================================================

extract_chapter() {
    local filename="$1"
    local base

    base="${filename%.cbz}"

    # ------------------------------------------------------
    # 1. Explicit "Chapter" prefix ANYWHERE
    #
    # Examples:
    #   Chapter 1
    #   Chapter 01
    #   Chapter 001
    #   Chapter 72.5
    #   Vol.01 Chapter 0001
    #   Volume 2 - Chapter 10
    # ------------------------------------------------------

    if [[ "$base" =~ [Cc][Hh][Aa][Pp][Tt][Ee][Rr][[:space:]_.-]*([0-9]+([.][0-9]+)?)($|[[:space:]_.-]) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # ------------------------------------------------------
    # 2. Explicit "Ch" prefix ANYWHERE
    #
    # Examples:
    #   Ch 100
    #   Ch. 100
    #   Ch.100
    #   ch100
    #   Vol.01 Ch.0001
    #   Vol.02 Ch.0010.5
    #
    # The character immediately before "Ch" must not be an
    # alphabetic character. This prevents matching things
    # like:
    #
    #   Character...
    #   Chronicles...
    #
    # ------------------------------------------------------

    if [[ "$base" =~ (^|[^[:alpha:]])[Cc][Hh][[:space:]]*\.?[[:space:]]*([0-9]+([.][0-9]+)?)($|[[:space:]_.-]) ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
    fi

    # ------------------------------------------------------
    # 3. Filename begins directly with a number
    #
    # Examples:
    #   1
    #   01
    #   001
    #   72.5
    #   12 - Title
    #
    # This is deliberately checked AFTER explicit chapter
    # prefixes so that:
    #
    #   Vol.01 Ch.0001
    #
    # does not incorrectly become chapter 01.
    # ------------------------------------------------------

    if [[ "$base" =~ ^([0-9]+([.][0-9]+)?)($|[[:space:]_.-]) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# ==========================================================
# AUTO-RECOVER INTERRUPTED RUNS
# ==========================================================

tmpfiles=( ch*.cbz.tmp )

if [[ ${#tmpfiles[@]} -gt 0 ]]; then
    echo
    echo "Detected interrupted run — attempting recovery..."

    for tmpf in "${tmpfiles[@]}"; do
        target="${tmpf%.tmp}"

        if [[ -e "$target" ]]; then
            echo "Recovery skipped: $target already exists"
            echo "  Temporary file retained: $tmpf"
            continue
        fi

        if $DRY_RUN; then
            echo "[DRY RUN][RECOVER] $tmpf → $target"
        else
            echo "Recovering $tmpf → $target"

            if ! mv -- "$tmpf" "$target"; then
                echo "ERROR: failed to recover $tmpf"
            fi
        fi
    done

    echo
fi

# ==========================================================
# Read all CBZ filenames BEFORE renaming
# ==========================================================

files=( *.cbz )

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No CBZ files found in $TARGET_DIR"
    exit 0
fi

# ==========================================================
# Rename files
# ==========================================================

for f in "${files[@]}"; do

    # ------------------------------------------------------
    # Skip canonical files:
    #
    # ch000.cbz
    # ch001.cbz
    # ch072.5.cbz
    # ch100.cbz
    # ------------------------------------------------------

    if [[ "$f" =~ ^ch[0-9]{3}(\.[0-9]+)?\.cbz$ ]]; then
        echo "Skipping already renamed file: $f"
        continue
    fi

    # ------------------------------------------------------
    # Extract chapter number
    # ------------------------------------------------------

    chapter="$(extract_chapter "$f" || true)"

    if [[ -z "$chapter" ]]; then
        echo "Skipping $f: no chapter number found"
        continue
    fi

    # ------------------------------------------------------
    # Generate canonical filename
    # ------------------------------------------------------

    new="$(make_canonical_name "$chapter")"

    if [[ -z "$new" ]]; then
        echo "Skipping $f: unable to create canonical filename"
        continue
    fi

    # Already same name
    if [[ "$f" == "$new" ]]; then
        echo "Skipping already correct file: $f"
        continue
    fi

    # ------------------------------------------------------
    # Target already exists
    # ------------------------------------------------------

    if [[ -e "$new" ]]; then

        tmp="${new}.tmp"

        echo "Target exists: $new"
        echo "  Staging: $f → $tmp"

        if $DRY_RUN; then
            echo "[DRY RUN] $f → $tmp"
        else

            # Do not overwrite an existing temporary file.
            if [[ -e "$tmp" ]]; then
                echo "ERROR: temporary target already exists:"
                echo "  $tmp"
                echo "Skipping: $f"
                continue
            fi

            if ! mv -- "$f" "$tmp"; then
                echo "ERROR: failed to stage:"
                echo "  $f"
            fi
        fi

    else

        # --------------------------------------------------
        # Normal rename
        # --------------------------------------------------

        if $DRY_RUN; then
            echo "[DRY RUN] $f → $new"
        else

            if ! mv -- "$f" "$new"; then
                echo "ERROR: failed to rename:"
                echo "  $f"
                echo "  → $new"
            fi
        fi
    fi
done

# ==========================================================
# Finalize staged files
# ==========================================================

tmpfiles=( ch*.cbz.tmp )

if [[ ${#tmpfiles[@]} -gt 0 ]]; then

    echo
    echo "Finalizing staged files..."

    for tmpf in "${tmpfiles[@]}"; do

        target="${tmpf%.tmp}"

        if [[ -e "$target" ]]; then
            echo "Finalize skipped: $target already exists"
            echo "  Temporary file retained: $tmpf"
            continue
        fi

        if $DRY_RUN; then
            echo "[DRY RUN] $tmpf → $target"
        else
            echo "Renaming $tmpf → $target"

            if ! mv -- "$tmpf" "$target"; then
                echo "ERROR: failed to finalize:"
                echo "  $tmpf"
                echo "  → $target"
            fi
        fi
    done
fi

echo
echo "Done."
