# CBZ Chapter Renamer (Rust)

Safely rename CBZ files like `10.cbz` ➔ `ch010.cbz`, with auto-recovery for interrupted runs.

---

## Features

- **Safe renaming**: skips already renamed files.
- **Dry-run mode** by default, no files are changed.
- **Apply mode**: actually rename files with `--apply`.
- **Auto-recovery**: resumes interrupted runs by processing leftover `.tmp` files.
- **Collision-safe**: uses `.tmp` staging to avoid overwriting existing files.
- **Numeric parsing**: preserves leading zeros (e.g., `010` ➔ `ch010`).
- **Two-pass renaming**: first stage `.tmp` for conflicts, then finalize.

---

## Usage

```bash
# Dry-run (default)
cbz_chapter_fix --dir "/path/to/cbz/files"

# Apply changes
cbz_chapter_fix --dir "/path/to/cbz/files" --apply
```

### Flags

- `--dir` / `-d` **[optional]**: Target directory (defaults to current directory).
- `--apply`: Actually rename files (otherwise dry-run).
- `--help`: Show usage info.

---

## Compilation

Requires [Rust toolchain](https://www.rust-lang.org/tools/install).

```bash
# Compile one-off binary
cargo build --release

# Binary location
./target/release/cbz_chapter_fix
```

---

## Safety Notes

- Re-running is safe; already renamed files are skipped.
- `.tmp` files from interrupted runs are automatically recovered.
- Conflicting names are staged before final rename to prevent data loss.

