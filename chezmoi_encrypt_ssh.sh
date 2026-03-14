#!/bin/bash
set -e

# Define files to exclude (separated by space)
EXCLUDE_FILES=("config" "known_hosts" "known_hosts.old" "authorized_keys")

# List all files in ~/.ssh directory
echo "Listing files in ~/.ssh directory..."
for file in ~/.ssh/*; do
    filename=$(basename "$file")
    # Skip excluded files and directories
    if [ -f "$file" ]; then
        should_exclude=0
        for exclude in "${EXCLUDE_FILES[@]}"; do
            if [ "$filename" == "$exclude" ]; then
                should_exclude=1
                break
            fi
        done
        
        if [ $should_exclude -eq 0 ]; then
            echo "Encrypting $filename..."
            chezmoi add --encrypt ~/.ssh/"$filename"
        else
            echo "Skipping excluded file: $filename"
        fi
    fi
done

echo "SSH files encryption completed."