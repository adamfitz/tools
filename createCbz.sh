#!/bin/bash

count=0

# Iterate through each subdirectory in the current directory
for subDir in */; do
    if [ -d "$subDir" ]; then
        # Create padded CBZ name
        cbz_name=$(printf "ch%03d.cbz" "$count")

        # Create CBZ if there are files
        if compgen -G "$subDir"* > /dev/null; then
            zip -q -j "${cbz_name}" "$subDir"*
            echo "created:  ${cbz_name}"
        fi

        ((count++))
    fi
done

