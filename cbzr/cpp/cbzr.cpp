#include <iostream>
#include <filesystem>
#include <vector>
#include <string>
#include <algorithm>
#include <cctype>
#include <sstream>

namespace fs = std::filesystem;

// Check if string is all digits
bool is_number(const std::string& s) {
    return !s.empty() && std::all_of(s.begin(), s.end(), ::isdigit);
}

// Pad number with leading zeros to width 3
std::string zero_pad(const std::string& s, int width = 3) {
    std::ostringstream oss;
    oss.fill('0');
    oss.width(width);
    oss << s;
    return oss.str();
}

int main(int argc, char* argv[]) {
    fs::path dir;
    bool apply = false;

    // --- Simple command-line parsing ---
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "-d" || arg == "--dir") && i + 1 < argc) {
            dir = argv[++i];
        } else if (arg == "-a" || arg == "--apply") {
            apply = true;
        } else {
            std::cerr << "Unknown argument: " << arg << "\n";
            return 1;
        }
    }

    if (dir.empty()) {
        std::cerr << "Error: --dir argument is required\n";
        return 1;
    }

    if (!fs::exists(dir) || !fs::is_directory(dir)) {
        std::cerr << "Error: " << dir << " is not a valid directory\n";
        return 1;
    }

    std::cout << "Processing CBZ files in: " << dir << "\n";
    if (apply) {
        std::cout << "Applying changes (files WILL be renamed)\n";
    } else {
        std::cout << "Running in DRY RUN mode (no files will be renamed)\n";
        std::cout << "Use --apply to perform changes\n";
    }

    // --- Recover leftover temp files from interrupted runs ---
    for (auto& entry : fs::directory_iterator(dir)) {
        auto path = entry.path();
        if (path.extension() == ".tmp") {
            fs::path target = path;
            target.replace_extension(".cbz");
            std::cout << "[RECOVER] " << path.filename() << " → " << target.filename() << "\n";
            if (apply) {
                try {
                    fs::rename(path, target);
                } catch (fs::filesystem_error& e) {
                    std::cerr << "Failed to recover " << path << ": " << e.what() << "\n";
                }
            }
        }
    }

    // --- Collect CBZ files ---
    std::vector<fs::path> files;
    for (auto& entry : fs::directory_iterator(dir)) {
        auto path = entry.path();
        if (path.extension() == ".cbz") {
            files.push_back(path);
        }
    }

    std::sort(files.begin(), files.end());

    for (auto& file : files) {
        std::string file_name = file.filename().string();

        // Skip already renamed
        if (file_name.rfind("ch", 0) == 0) {
            std::cout << "Skipping already renamed file: " << file_name << "\n";
            continue;
        }

        // Extract leading number
        std::string number = file_name.substr(0, file_name.find('.'));
        if (!is_number(number)) {
            std::cout << "Skipping " << file_name << ": no leading number found\n";
            continue;
        }

        std::string new_name = "ch" + zero_pad(number) + ".cbz";
        fs::path target_path = dir / new_name;

        if (apply) {
            if (fs::exists(target_path)) {
                std::cout << "mv: overwrite '" << target_path << "'? [y/N] ";
                std::cout.flush();
                std::string input;
                std::getline(std::cin, input);
                if (input != "y" && input != "Y") {
                    std::cout << "Skipped " << target_path << "\n";
                    continue;
                }
            }

            fs::path tmp_path = target_path;
            tmp_path.replace_extension(".cbz.tmp");

            try {
                fs::rename(file, tmp_path);
                fs::rename(tmp_path, target_path);
                std::cout << "Renamed " << file.filename() << " → " << target_path.filename() << "\n";
            } catch (fs::filesystem_error& e) {
                std::cerr << "Failed to rename " << file << " → " << target_path << ": " << e.what() << "\n";
            }
        } else {
            std::cout << "[DRY RUN] " << file_name << " → " << new_name << "\n";
        }
    }

    std::cout << "Done.\n";
    return 0;
}
