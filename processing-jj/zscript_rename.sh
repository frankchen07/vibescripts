#!/bin/bash

# Loop through all .mov files in the current directory
for file in *.mov; do
    # Check if the filename contains "-compressed"
    if [[ "$file" == *"-compressed.mov" ]]; then
        # Generate the new filename by removing "-compressed"
        new_file="${file//-compressed/}"
        
        # Check if the non-suffixed file exists and delete it first
        if [[ -f "$new_file" ]]; then
            echo "Moving to trash: $new_file"
            trash "$new_file"
        fi
        
        # Rename the file
        mv "$file" "$new_file"
        
        echo "Renamed: $file -> $new_file"
    else
        echo "Skipped: $file (does not contain '-compressed')"
    fi
done

echo "Renaming process completed!"
