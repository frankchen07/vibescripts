#!/bin/bash

# Directory to process (default is the current directory)
DIR=${1:-.}
PARENT_DIR=$(cd "$DIR/.." && pwd)

# Ensure necessary tools are available
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is not installed. Exiting." >&2; exit 1; }

# Step 2: Compress files first
for input_file in "$DIR"/*.mov; do
  
  # Skip specific files
  if [[ "$input_file" == *"/10p-append-4kto720p.mov" ]]; then
    echo "Skipping $input_file: Excluded file."
    continue
  fi

  filename=$(basename -- "$input_file")
  extension="${filename##*.}"
  name="${filename%.*}"

  # Create compressed file
  compressed_file="$DIR/${name}-compressed.${extension}"
  if [[ ! -f "$compressed_file" ]]; then
    echo "Compressing: $input_file -> $compressed_file"
    ffmpeg -i "$input_file" \
      -c:v libx264 -profile:v high -level 4.1 -preset veryfast -crf 23 \
      -vf "scale=1280:720,fps=30" \
      -b:v 8083k \
      -c:a aac -b:a 191k -ar 44100 \
      -movflags +faststart \
      "$compressed_file"
  else
    echo "Compressed file already exists: $compressed_file"
  fi
done

# Step 1.5: Handle compressed files - trash and rename compressed files
for compressed_file in "$DIR"/*-compressed.mov; do
    if [[ -f "$compressed_file" ]]; then
        # Generate the new filename by removing "-compressed"
        new_file="${compressed_file//-compressed/}"
        
        # Check if the non-suffixed file exists and move it to trash first
        if [[ -f "$new_file" ]]; then
            echo "Moving to trash: $new_file"
            trash "$new_file"
        fi
        
        # Rename the compressed file
        mv "$compressed_file" "$new_file"
        
        echo "Renamed: $compressed_file -> $new_file"
    fi
done

# Step 2: Process compressed files
shopt -s nullglob
mov_files=("$DIR"/*.mov)
if [ ${#mov_files[@]} -eq 0 ]; then
  echo "No .mov files found in the specified directory."
  exit 1
fi

for input_file in "${mov_files[@]}"; do
  # Skip specific files
  if [[ "$input_file" == *"/10p-append-4kto720p.mov" ]]; then
    echo "Skipping $input_file: Excluded file."
    continue
  fi

  filename=$(basename -- "$input_file")
  extension="${filename##*.}"
  name="${filename%.*}"

  # Create -originalnosound file
  ns_output_file="$DIR/${name}-originalnosound.${extension}"
  if [[ ! -f "$ns_output_file" ]]; then
    echo "Removing audio from $input_file -> $ns_output_file"
    ffmpeg -i "$input_file" -c:v copy -an "$ns_output_file"
  else
    echo "Audio-free file already exists: $ns_output_file"
  fi

  # Use "-originalnosound" file for further processing
  source_file="$ns_output_file"
  prepend_file="$DIR/10p-append-4kto720p.mov"

  # Create a temporary list file for concatenation
  concat_file="file-list.txt"
  echo "file '$prepend_file'" > "$concat_file"
  echo "file '$source_file'" >> "$concat_file"

  # Generate concatenated output filename
  concat_output_file="$DIR/${name}-ytready.${extension}"
  if [[ ! -f "$concat_output_file" ]]; then
    echo "Concatenating to $concat_output_file"
    ffmpeg -f concat -safe 0 -i "$concat_file" -c copy "$concat_output_file"
  else
    echo "Screened file already exists: $concat_output_file"
  fi

  # Clean up the temporary file list
  rm -f "$concat_file"

  # Move files as specified
  if [[ -f "$concat_output_file" ]]; then
    mv "$concat_output_file" "$PARENT_DIR/"
  fi

  if [[ -f "$ns_output_file" ]]; then
    rm -f "$ns_output_file"
  fi

done

echo "All tasks completed successfully!"
