#!/usr/bin/env bash

#
# cbz_dedup.sh
#
# Find duplicate CBZ chapters within each directory.
#
# Canonical keeper:
#   ch000.cbz
#   ch001.cbz
#   ch123.cbz
#
# Canonical files are NEVER reported as duplicates.
#
# Examples of non-canonical filenames:
#   Vol.01 Ch.0001 (en) [Reaper_Scans].cbz
#   Vol.01 Ch.0001 - Chapter 1.cbz
#   chapter001.cbz
#   chapter1.cbz
#   ch01.cbz
#   Ch.001 (en).cbz
#
# Duplicate checking is performed separately in each directory.
#
# NO files are deleted or modified.
# This script is always dry-run/report-only.
#

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"

ROOT_DIR="."
REPORT_FILE=""
DUPLICATES_ONLY=0

# ============================================================
# Usage
# ============================================================

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME [OPTIONS] [DIRECTORY]

Options:

  -d, --duplicates-only
        Output ONLY duplicate file paths.
        One file per line.
        No headers.
        No chapter numbers.
        No keeper names.
        No labels.

  -r, --report FILE
        Write output to FILE as well as stdout.

  -n, --dry-run
        Report only. No files are modified.
        This is always the default.

  -h, --help
        Show this help.

Examples:

  $SCRIPT_NAME .

  $SCRIPT_NAME . --duplicates-only

  $SCRIPT_NAME --duplicates-only .

  $SCRIPT_NAME --report manga_duplicate_chapters.txt . --duplicates-only

  $SCRIPT_NAME . --duplicates-only --report manga_duplicate_chapters.txt

EOF
}

# ============================================================
# Parse arguments
# ============================================================

while [[ $# -gt 0 ]]; do

    case "$1" in

        -d|--duplicates-only)
            DUPLICATES_ONLY=1
            shift
            ;;

        -r|--report)
            [[ $# -ge 2 ]] || {
                echo "Error: --report requires a filename" >&2
                exit 1
            }

            REPORT_FILE="$2"
            shift 2
            ;;

        -n|--dry-run)
            # Always dry-run. Accepted for compatibility.
            shift
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        --)
            shift

            if [[ $# -gt 1 ]]; then
                echo "Error: only one directory may be specified" >&2
                exit 1
            fi

            if [[ $# -eq 1 ]]; then
                ROOT_DIR="$1"
            fi

            shift
            ;;

        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;

        *)
            if [[ "$ROOT_DIR" != "." ]]; then
                echo "Error: only one directory may be specified" >&2
                exit 1
            fi

            ROOT_DIR="$1"
            shift
            ;;

    esac

done

# ============================================================
# Validate directory
# ============================================================

if [[ ! -d "$ROOT_DIR" ]]; then
    echo "Error: directory does not exist: $ROOT_DIR" >&2
    exit 1
fi

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

# ============================================================
# Prepare report
# ============================================================

if [[ -n "$REPORT_FILE" ]]; then
    : > "$REPORT_FILE" || {
        echo "Error: cannot write report: $REPORT_FILE" >&2
        exit 1
    }
fi

# ============================================================
# Output function
#
# In duplicates-only mode this is still just one line.
# ============================================================

output() {
    printf '%s\n' "$1"

    if [[ -n "$REPORT_FILE" ]]; then
        printf '%s\n' "$1" >> "$REPORT_FILE"
    fi
}

# ============================================================
# Extract chapter number
#
# Recognises:
#
#   ch1
#   ch01
#   ch001
#   Ch.001
#   Ch 001
#   Ch-001
#   chapter1
#   chapter001
#   chatper001
#
# anywhere in the filename.
# ============================================================

extract_chapter() {

    local filename="$1"
    local base
    local chapter

    base="${filename##*/}"

    # Remove extension.
    base="${base%.[cC][bB][zZ]}"

    # Lowercase.
    base="${base,,}"

    if [[ "$base" =~ (^|[^a-z])(chapter|chatper|ch)[[:space:]_.-]*([0-9]+) ]]; then

        chapter="${BASH_REMATCH[3]}"

        # Remove leading zeroes.
        chapter="${chapter#"${chapter%%[!0]*}"}"

        # If number was all zeroes.
        if [[ -z "$chapter" ]]; then
            chapter="0"
        fi

        printf '%s\n' "$chapter"
        return 0
    fi

    return 1
}

# ============================================================
# Is canonical?
#
# ONLY exactly:
#
#   ch000.cbz
#   ch001.cbz
#   ch123.cbz
#
# qualifies.
# ============================================================

is_canonical() {
    local filename="$1"

    [[ "$filename" =~ ^ch[0-9]{3}\.cbz$ ]]
}

# ============================================================
# Temporary directory
# ============================================================

TMP_DIR="$(mktemp -d)" || {
    echo "Error: unable to create temporary directory" >&2
    exit 1
}

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# ============================================================
# Find directories containing CBZ files
# ============================================================

mapfile -d '' DIRECTORIES < <(
    find "$ROOT_DIR" \
        -type f \
        -iname '*.cbz' \
        -printf '%h\0' |
    sort -zu
)

# ============================================================
# ============================================================
#
# DUPLICATES ONLY
#
# THIS IS THE IMPORTANT PART.
#
# Output is STRICTLY:
#
# /full/path/file1.cbz
# /full/path/file2.cbz
# /full/path/file3.cbz
#
# Nothing else.
#
# ============================================================
# ============================================================

if (( DUPLICATES_ONLY )); then

    for DIR in "${DIRECTORIES[@]}"; do

        CHAPTER_FILE="$TMP_DIR/chapters"

        : > "$CHAPTER_FILE"

        # ----------------------------------------------------
        # Read CBZ files directly in this directory.
        # ----------------------------------------------------

        while IFS= read -r -d '' FILE; do

            BASENAME="${FILE##*/}"

            if CHAPTER="$(extract_chapter "$BASENAME")"; then

                printf '%s\t%s\t%s\n' \
                    "$CHAPTER" \
                    "$BASENAME" \
                    "$FILE" \
                    >> "$CHAPTER_FILE"

            fi

        done < <(
            find "$DIR" \
                -maxdepth 1 \
                -type f \
                -iname '*.cbz' \
                -print0
        )

        [[ -s "$CHAPTER_FILE" ]] || continue

        # ----------------------------------------------------
        # Determine which chapter numbers occur more than once.
        # ----------------------------------------------------

        while IFS= read -r CHAPTER; do

            [[ -n "$CHAPTER" ]] || continue

            COUNT="$(
                awk -F '\t' \
                    -v chapter="$CHAPTER" \
                    '$1 == chapter { n++ } END { print n+0 }' \
                    "$CHAPTER_FILE"
            )"

            # Only one file = not a duplicate.
            (( COUNT > 1 )) || continue

            # ------------------------------------------------
            # Determine canonical filename.
            # ------------------------------------------------

            printf -v PADDED '%03d' "$CHAPTER"

            CANONICAL="ch${PADDED}.cbz"

            # ------------------------------------------------
            # OUTPUT ONLY NON-CANONICAL FILES.
            #
            # No labels.
            # No formatting.
            # No headers.
            # No keeper.
            # No chapter.
            # ------------------------------------------------

            while IFS=$'\t' read -r C BASENAME FULLPATH; do

                [[ "$C" == "$CHAPTER" ]] || continue

                # NEVER output canonical keeper.
                if [[ "$BASENAME" == "$CANONICAL" ]]; then
                    continue
                fi

                output "$FULLPATH"

            done < "$CHAPTER_FILE"

        done < <(
            cut -f1 "$CHAPTER_FILE" |
            sort -n |
            uniq
        )

    done

    exit 0
fi

# ============================================================
# NORMAL REPORT MODE
# ============================================================

output "============================================================"
output "CBZ DUPLICATE CHAPTER REPORT"
output "============================================================"
output ""
output "Root directory : $ROOT_DIR"
output "Mode           : DRY RUN / REPORT ONLY"
output ""
output "Canonical keeper format:"
output "  chNNN.cbz"
output ""
output "Canonical files are NEVER marked as duplicates."
output "Duplicate checking is performed separately in each directory."
output ""
output "============================================================"

TOTAL_DUPLICATES=0
TOTAL_DIRECTORIES=0

# ============================================================
# Process directories
# ============================================================

for DIR in "${DIRECTORIES[@]}"; do

    CHAPTER_FILE="$TMP_DIR/chapters"

    : > "$CHAPTER_FILE"

    ((TOTAL_DIRECTORIES++))

    # --------------------------------------------------------
    # Collect files
    # --------------------------------------------------------

    while IFS= read -r -d '' FILE; do

        BASENAME="${FILE##*/}"

        if CHAPTER="$(extract_chapter "$BASENAME")"; then

            printf '%s\t%s\t%s\n' \
                "$CHAPTER" \
                "$BASENAME" \
                "$FILE" \
                >> "$CHAPTER_FILE"

        fi

    done < <(
        find "$DIR" \
            -maxdepth 1 \
            -type f \
            -iname '*.cbz' \
            -print0 |
        sort -z
    )

    [[ -s "$CHAPTER_FILE" ]] || continue

    output ""
    output "DIRECTORY:"
    output "  $DIR"
    output ""

    output "  CBZ files:"

    while IFS= read -r -d '' FILE; do

        BASENAME="${FILE##*/}"

        if is_canonical "$BASENAME"; then

            output "    [KEEP]        $BASENAME"

        elif extract_chapter "$BASENAME" >/dev/null 2>&1; then

            output "    [CHECK]       $BASENAME"

        else

            output "    [NO CHAPTER]  $BASENAME"

        fi

    done < <(
        find "$DIR" \
            -maxdepth 1 \
            -type f \
            -iname '*.cbz' \
            -print0 |
        sort -z
    )

    # --------------------------------------------------------
    # Find duplicate chapters
    # --------------------------------------------------------

    while IFS= read -r CHAPTER; do

        COUNT="$(
            awk -F '\t' \
                -v chapter="$CHAPTER" \
                '$1 == chapter { n++ } END { print n+0 }' \
                "$CHAPTER_FILE"
        )"

        (( COUNT > 1 )) || continue

        printf -v PADDED '%03d' "$CHAPTER"

        CANONICAL="ch${PADDED}.cbz"

        output ""
        output "------------------------------------------------------------"
        output "DUPLICATES FOUND"
        output "DIRECTORY: $DIR"
        output "------------------------------------------------------------"
        output ""
        output "  Chapter $CHAPTER"
        output "  Keeper: $CANONICAL"
        output "  Duplicate files:"

        while IFS=$'\t' read -r C BASENAME FULLPATH; do

            [[ "$C" == "$CHAPTER" ]] || continue

            if [[ "$BASENAME" == "$CANONICAL" ]]; then
                continue
            fi

            output "    [DUPLICATE] $BASENAME"

            ((TOTAL_DUPLICATES++))

        done < "$CHAPTER_FILE"

    done < <(
        cut -f1 "$CHAPTER_FILE" |
        sort -n |
        uniq
    )

done

# ============================================================
# Summary
# ============================================================

output ""
output "============================================================"
output "SUMMARY"
output "============================================================"
output ""
output "Directories scanned : $TOTAL_DIRECTORIES"
output "Duplicate files     : $TOTAL_DUPLICATES"
output ""
output "No files were deleted."
output "No files were modified."
output "DRY RUN COMPLETE."
output "============================================================"