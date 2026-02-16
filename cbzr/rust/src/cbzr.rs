use clap::{Arg, Command};
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;

fn main() {
    let matches = Command::new("cbzr")
        .version("0.1.0")
        .author("Adam")
        .about("Safely renames CBZ files with auto-recovery for interrupted runs")
        .arg(
            Arg::new("dir")
                .short('d')
                .long("dir")
                .value_name("PATH")
                .help("Directory containing CBZ files")
                .num_args(1)
                .required(true) // <- require the argument
        )
        .arg(
            Arg::new("apply")
                .short('a')
                .long("apply")
                .help("Actually apply changes instead of dry-run")
                .action(clap::ArgAction::SetTrue)
        )
        .get_matches();

    let dir = PathBuf::from(matches.get_one::<String>("dir").unwrap());
    let apply = matches.get_flag("apply");

    if !dir.is_dir() {
        eprintln!("Error: '{}' is not a valid directory.", dir.display());
        return;
    }

    println!("Processing CBZ files in: {}", dir.display());
    if apply {
        println!("Applying changes (files WILL be renamed)");
    } else {
        println!("Running in DRY RUN mode (no files will be renamed)");
        println!("Use --apply to perform changes");
    }

    // Recover leftover temp files from interrupted runs
    for entry in fs::read_dir(&dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().map(|s| s == "tmp").unwrap_or(false) {
            let target = path.with_extension("cbz");
            println!("[RECOVER] {:?} → {:?}", path.file_name().unwrap(), target.file_name().unwrap());
            if apply {
                fs::rename(&path, &target).unwrap_or_else(|e| eprintln!("Failed to recover {:?}: {}", path, e));
            }
        }
    }

    // Collect CBZ files
    let mut files: Vec<PathBuf> = fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| {
            let p = e.unwrap().path();
            if p.extension().map(|s| s == "cbz").unwrap_or(false) {
                Some(p)
            } else {
                None
            }
        })
        .collect();

    files.sort();

    for file in files {
        let file_name = file.file_name().unwrap().to_string_lossy();
        // Skip already renamed
        if file_name.starts_with("ch") {
            println!("Skipping already renamed file: {}", file_name);
            continue;
        }

        // Extract leading number (e.g., 019.cbz → 019)
        let number = file_name.split('.').next().unwrap();
        if !number.chars().all(|c| c.is_digit(10)) {
            println!("Skipping {}: no leading number found", file_name);
            continue;
        }

        let new_name = format!("ch{}.cbz", number);
        let target_path = dir.join(new_name.clone());

        if apply {
            if target_path.exists() {
                // Ask before overwriting
                print!("mv: overwrite '{}'? [y/N] ", target_path.display());
                io::stdout().flush().unwrap();
                let mut input = String::new();
                io::stdin().read_line(&mut input).unwrap();
                if !input.trim().eq_ignore_ascii_case("y") {
                    println!("Skipped {}", target_path.display());
                    continue;
                }
            }

            let tmp_path = target_path.with_extension("cbz.tmp");
            fs::rename(&file, &tmp_path).unwrap_or_else(|e| {
                eprintln!("Failed to rename {:?} → {:?}: {}", file, tmp_path, e);
            });
            fs::rename(&tmp_path, &target_path).unwrap_or_else(|e| {
                eprintln!("Failed to finalize {:?} → {:?}: {}", tmp_path, target_path, e);
            });
            println!("Renamed {:?} → {:?}", file.file_name().unwrap(), target_path.file_name().unwrap());
        } else {
            println!("[DRY RUN] {} → {}", file_name, new_name);
        }
    }

    println!("Done.");
}
