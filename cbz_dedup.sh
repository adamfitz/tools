#!/usr/bin/env bash

#
# cbz_dedup.sh
#
# Find duplicate CBZ chapter files ONLY when a corresponding
# canonical chNNN[.PART].cbz file already exists in the SAME
# directory.
#
# Examples:
#
#   ch001.cbz
#   Vol.01 Ch.0001 (en).cbz
#
#   -> Vol.01 Ch.0001 (en).cbz is a duplicate
#
# Part chapters are supported:
#
#   ch029.cbz
#   Ch.0029.cbz
#
#   ch029.1.cbz
#   Ch.0029.1.cbz
#
#   ch029.10.cbz
#   Ch.0029.10.cbz
#
# Part numbers are part of the chapter identity.
#
# Therefore:
#
#   29
#   29.1
#   29.10
#   29.11
#
# are FOUR different chapter identifiers.
#
# IMPORTANT:
#
# If ch029.cbz does NOT exist:
#
#   Ch.0029
#   Ch.0029.1
#   Ch.0029.10
#   Ch.0029.11
#
# are ALL ignored.
#
# Likewise, if ch029.10.cbz does NOT exist,
# Ch.0029.10 is ignored.
#
# No files are deleted or modified.
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
            # Always report-only.
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
# Output
# ============================================================

output() {

    printf '%s\n' "$1"

    if [[ -n "$REPORT_FILE" ]]; then
        printf '%s\n' "$1" >> "$REPORT_FILE"
    fi

}

# ============================================================
# Normalize chapter identifier
#
# Input examples:
#
#   0001
#   0029
#   0029.1
#   0029.10
#   0001.05
#
# Output:
#
#   1
#   29
#   29.1
#   29.10
#   1.5
#
# This means:
#
#   ch029.10
#   Ch.0029.10
#
# refer to the same chapter.
# ============================================================

normalize_chapter() {

    local chapter="$1"
    local main
    local part

    if [[ "$chapter" == *.* ]]; then

        main="${chapter%%.*}"
        part="${chapter#*.}"

    else

        main="$chapter"
        part=""

    fi

    # Remove leading zeroes from main chapter.
    main="${main#"${main%%[!0]*}"}"

    [[ -n "$main" ]] || main="0"

    if [[ -n "$part" ]]; then

        # Remove leading zeroes from part.
        part="${part#"${part%%[!0]*}"}"

        [[ -n "$part" ]] || part="0"

        printf '%s.%s\n' "$main" "$part"

    else

        printf '%s\n' "$main"

    fi

}

# ============================================================
# Extract complete chapter identifier from a filename.
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
# And part chapters:
#
#   Ch.001.1
#   Ch.001.5
#   Ch.001.10
#   Chapter 29.1
#   Chapter 29.10
#
# The complete numeric identifier is extracted.
#
# Examples:
#
#   Ch.0029.cbz
#       -> 29
#
#   Ch.0029.10 - Something.cbz
#       -> 29.10
#
#   Ch.0029.10.cbz
#       -> 29.10
#
# ============================================================

extract_chapter() {

    local filename="$1"
    local base
    local chapter
    local main
    local part

    base="${filename##*/}"

    # Remove .cbz extension.
    base="${base%.[cC][bB][zZ]}"

    # Lowercase.
    base="${base,,}"

    #
    # IMPORTANT:
    #
    # The optional .PART is included in the match.
    #
    # The character after the chapter identifier must NOT
    # be another digit or another dot.
    #
    if [[ "$base" =~ (^|[^a-z])(chapter|chatper|ch)[[:space:]_.-]*([0-9]+)(\.([0-9]+))?([^0-9.]|$) ]]; then

        main="${BASH_REMATCH[3]}"
        part="${BASH_REMATCH[5]:-}"

        # Normalize main number.
        main="${main#"${main%%[!0]*}"}"

        [[ -n "$main" ]] || main="0"

        if [[ -n "$part" ]]; then

            part="${part#"${part%%[!0]*}"}"

            [[ -n "$part" ]] || part="0"

            chapter="${main}.${part}"

        else

            chapter="$main"

        fi

        printf '%s\n' "$chapter"
        return 0

    fi

    return 1
}

# ============================================================
# Is canonical?
#
# Canonical files are:
#
#   ch000.cbz
#   ch001.cbz
#   ch029.cbz
#
# And part chapters:
#
#   ch029.1.cbz
#   ch029.5.cbz
#   ch029.10.cbz
#
# Exactly three digits are required for the main chapter.
# The optional part may contain any number of digits.
# ============================================================

is_canonical() {

    local filename="$1"

    [[ "$filename" =~ ^ch[0-9]{3}(\.[0-9]+)?\.cbz$ ]]

}

# ============================================================
# Extract canonical chapter identifier.
#
# ch029.cbz
#     -> 29
#
# ch029.10.cbz
#     -> 29.10
# ============================================================

canonical_chapter() {

    local filename="$1"
    local chapter

    chapter="${filename#ch}"
    chapter="${chapter%.cbz}"

    normalize_chapter "$chapter"

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
# DUPLICATES ONLY
#
# The algorithm is:
#
#   1. Find canonical chNNN[.PART].cbz files.
#
#   2. If there are none:
#          DO NOTHING.
#
#   3. Build a list of canonical chapter identifiers.
#
#   4. Examine alternate filenames.
#
#   5. Only output an alternate when its COMPLETE chapter
#      identifier exists in the canonical list.
#
# ============================================================

if (( DUPLICATES_ONLY )); then

    for DIR in "${DIRECTORIES[@]}"; do

        CANONICAL_FILE="$TMP_DIR/canonical"

        : > "$CANONICAL_FILE"

        # ----------------------------------------------------
        # Find canonical files in THIS directory only.
        # ----------------------------------------------------

        while IFS= read -r -d '' FILE; do

            BASENAME="${FILE##*/}"

            if is_canonical "$BASENAME"; then

                CHAPTER="$(canonical_chapter "$BASENAME")"

                printf '%s\t%s\n' \
                    "$CHAPTER" \
                    "$BASENAME" \
                    >> "$CANONICAL_FILE"

            fi

        done < <(
            find "$DIR" \
                -maxdepth 1 \
                -type f \
                -name 'ch[0-9][0-9][0-9]*.cbz' \
                -print0 |
            sort -z
        )

        # ----------------------------------------------------
        # NO canonical files in this directory.
        #
        # This is the critical condition.
        #
        # Nothing in this directory can be a duplicate.
        # ----------------------------------------------------

        [[ -s "$CANONICAL_FILE" ]] || continue

        # ----------------------------------------------------
        # Examine every non-canonical CBZ in this directory.
        # ----------------------------------------------------

        while IFS= read -r -d '' FILE; do

            BASENAME="${FILE##*/}"

            # Canonical files are never duplicates.
            if is_canonical "$BASENAME"; then
                continue
            fi

            # Extract COMPLETE chapter identifier.
            if ! CHAPTER="$(extract_chapter "$BASENAME")"; then
                continue
            fi

            # ------------------------------------------------
            # ONLY report if the exact chapter identifier has
            # an existing canonical file.
            #
            # Examples:
            #
            # 29       requires ch029.cbz
            # 29.1     requires ch029.1.cbz
            # 29.10    requires ch029.10.cbz
            # ------------------------------------------------

            if awk -F '\t' \
                -v chapter="$CHAPTER" \
                '$1 == chapter { found=1; exit } END { exit !found }' \
                "$CANONICAL_FILE"
            then

                output "$FILE"

            fi

        done < <(
            find "$DIR" \
                -maxdepth 1 \
                -type f \
                -iname '*.cbz' \
                -print0 |
            sort -z
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
output "Canonical format:"
output "  chNNN.cbz"
output "  chNNN.PART.cbz"
output ""
output "A file is only considered a duplicate when the corresponding"
output "canonical file already exists in the SAME directory."
output ""
output "Part chapters are treated as separate chapter identifiers."
output ""
output "Examples:"
output "  ch029.cbz       = chapter 29"
output "  ch029.1.cbz     = chapter 29.1"
output "  ch029.10.cbz    = chapter 29.10"
output ""
output "No cross-directory duplicate detection is performed."
output "Canonical files are NEVER marked as duplicates."
output ""
output "============================================================"

TOTAL_DUPLICATES=0
TOTAL_DIRECTORIES=0

# ============================================================
# Process directories
# ============================================================

for DIR in "${DIRECTORIES[@]}"; do

    ((TOTAL_DIRECTORIES++))

    CANONICAL_FILE="$TMP_DIR/canonical"

    : > "$CANONICAL_FILE"

    # --------------------------------------------------------
    # Find canonical files in THIS directory.
    # --------------------------------------------------------

    while IFS= read -r -d '' FILE; do

        BASENAME="${FILE##*/}"

        if is_canonical "$BASENAME"; then

            CHAPTER="$(canonical_chapter "$BASENAME")"

            printf '%s\t%s\t%s\n' \
                "$CHAPTER" \
                "$BASENAME" \
                "$FILE" \
                >> "$CANONICAL_FILE"

        fi

    done < <(
        find "$DIR" \
            -maxdepth 1 \
            -type f \
            -name 'ch[0-9][0-9][0-9]*.cbz' \
            -print0 |
        sort -z
    )

    # --------------------------------------------------------
    # No canonical files = no duplicate checking.
    # --------------------------------------------------------

    [[ -s "$CANONICAL_FILE" ]] || continue

    # --------------------------------------------------------
    # Directory header.
    # --------------------------------------------------------

    output ""
    output "DIRECTORY:"
    output "  $DIR"
    output ""

    output "  Canonical files:"

    while IFS=$'\t' read -r CHAPTER BASENAME FULLPATH; do

        output "    [KEEP] $BASENAME"

    done < "$CANONICAL_FILE"

    # --------------------------------------------------------
    # Check every CBZ against the canonical chapter list.
    # --------------------------------------------------------

    while IFS= read -r -d '' FILE; do

        BASENAME="${FILE##*/}"

        # Never report canonical files.
        if is_canonical "$BASENAME"; then
            continue
        fi

        # Ignore files without a recognizable chapter.
        if ! CHAPTER="$(extract_chapter "$BASENAME")"; then
            continue
        fi

        # ----------------------------------------------------
        # Find the corresponding canonical file.
        # ----------------------------------------------------

        KEEPER="$(
            awk -F '\t' \
                -v chapter="$CHAPTER" \
                '$1 == chapter {
                    print $2
                    exit
                }' \
                "$CANONICAL_FILE"
        )"

        # No canonical keeper for this chapter.
        #
        # Therefore this file is NOT a duplicate.
        [[ -n "$KEEPER" ]] || continue

        # ----------------------------------------------------
        # Duplicate found.
        # ----------------------------------------------------

        output ""

        output "------------------------------------------------------------"
        output "DUPLICATE FOUND"
        output "DIRECTORY: $DIR"
        output "------------------------------------------------------------"
        output ""
        output "  Chapter: $CHAPTER"
        output "  Keeper:  $KEEPER"
        output "  Duplicate:"
        output "    [DUPLICATE] $BASENAME"

        ((TOTAL_DUPLICATES++))

    done < <(
        find "$DIR" \
            -maxdepth 1 \
            -type f \
            -iname '*.cbz' \
            -print0 |
        sort -z
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
output "Only files with an existing canonical chNNN[.PART].cbz"
output "were checked."
output ""
output "No files were deleted."
output "No files were modified."
output "DRY RUN COMPLETE."
output "============================================================"