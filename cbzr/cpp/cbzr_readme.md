# CBZR - C++ CBZ Renamer

**CBZR** is a safe, CLI tool for renaming CBZ files in a directory. It is designed to mimic your Rust version but written in C++ with filesystem safety and auto-recovery features.

---

## Features

- **Automatic renaming**: Converts files like `1.cbz` → `ch001.cbz`, `19.cbz` → `ch019.cbz`.
- **Dry-run mode**: Preview all changes without modifying files.
- **Apply mode**: Actually rename files with `--apply`.
- **Auto-recovery**: Recovers leftover `.tmp` files from interrupted runs.
- **Skip already renamed files**: Files starting with `ch` are ignored.
- **Overwrite prompt**: Asks before overwriting existing files.
- **Simple error handling**: Handles missing directories or rename failures gracefully.

---

## Command-Line Usage

```bash
./cbzr --dir <PATH> [--apply]
```

### Flags

| Flag          | Description                                           |
|---------------|-------------------------------------------------------|
| `-d, --dir`   | Directory containing CBZ files (**required**)         |
| `-a, --apply` | Actually apply changes instead of dry-run (**optional**) |

### Examples

- Dry-run (preview):

```bash
./cbzr --dir "/mnt/webtoons/I'm the Grim Reaper"
```

- Apply changes (rename files):

```bash
./cbzr --dir "/mnt/webtoons/I'm the Grim Reaper" --apply
```

---

## Compilation

Requires **C++17** or newer. Compile using:

```bash
g++ -std=c++17 -o cbzr cbzr.cpp
```

Then run as shown above.

---

## How It Works

1. **Command-line parsing**: Reads `--dir` for target folder and optional `--apply`.
2. **Directory validation**: Checks if the given path exists and is a directory.
3. **Recovery**: Detects leftover `.tmp` files from interrupted runs and restores them.
4. **Collect files**: Gathers all `.cbz` files in the directory.
5. **Process files**:
   - Skips files already renamed (`chXXX.cbz`).
   - Extracts the leading number from filenames.
   - Zero-pads numbers to 3 digits.
   - Renames files with `.tmp` intermediate to safely handle interruptions.
6. **Overwrite handling**: Prompts if a target file already exists.
7. **Logging**: Prints status for all actions, including dry-run previews.

---

## Notes

- Always run without `--apply` first to preview changes.
- `.tmp` files are automatically recovered on the next run.
- Works on Linux, macOS, and Windows with C++17 support.

