#!/bin/bash

# Directory to process (default is the current directory)
DIR=${1:-.}
PARENT_DIR=$(cd "$DIR/.." && pwd)

# Define output directories
COMPRESSED_SAVE_DIR="$PARENT_DIR/rolling-compressed-save"
YTREADY_UPLOAD_DIR="$PARENT_DIR/rolling-ytready-upload-del"

# Create output directories if they don't exist
mkdir -p "$COMPRESSED_SAVE_DIR"
mkdir -p "$YTREADY_UPLOAD_DIR"

# Ensure necessary tools are available
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is not installed. Exiting." >&2; exit 1; }
command -v trash >/dev/null 2>&1 || { echo "trash is not installed. Exiting." >&2; exit 1; }

# Step 1: Compress files first
for input_file in "$DIR"/*.mov; do
  
  # Skip if no .mov files found (glob expansion)
  [[ ! -f "$input_file" ]] && continue
  
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
    ffmpeg -loglevel error -hide_banner -nostats -i "$input_file" \
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

# Step 2: Move compressed files to rolling-compressed-save and trash originals
for compressed_file in "$DIR"/*-compressed.mov; do
    if [[ -f "$compressed_file" ]]; then
        # Get the original filename (without -compressed suffix)
        original_file="${compressed_file//-compressed/}"
        
        # Move compressed file to rolling-compressed-save
        compressed_dest="$COMPRESSED_SAVE_DIR/$(basename "$compressed_file")"
        if [[ ! -f "$compressed_dest" ]]; then
            echo "Moving compressed file to rolling-compressed-save: $compressed_file"
            mv "$compressed_file" "$compressed_dest"
        else
            echo "Compressed file already exists in rolling-compressed-save: $compressed_dest"
            rm -f "$compressed_file"  # Remove duplicate
        fi
        
        # Trash the original file if it exists
        if [[ -f "$original_file" ]]; then
            echo "Moving original to trash: $original_file"
            trash "$original_file"
        fi
    fi
done

# Step 3: Process compressed files from rolling-compressed-save
shopt -s nullglob
mov_files=("$COMPRESSED_SAVE_DIR"/*.mov)
if [ ${#mov_files[@]} -eq 0 ]; then
  echo "No .mov files found in rolling-compressed-save directory."
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

  # Create -originalnosound file in the same directory
  ns_output_file="$COMPRESSED_SAVE_DIR/${name}-originalnosound.${extension}"
  if [[ ! -f "$ns_output_file" ]]; then
    echo "Removing audio from $input_file -> $ns_output_file"
    ffmpeg -loglevel error -hide_banner -nostats -i "$input_file" -c:v copy -an "$ns_output_file"
  else
    echo "Audio-free file already exists: $ns_output_file"
  fi

  # Use "-originalnosound" file for further processing
  source_file="$ns_output_file"
  prepend_file="$DIR/10p-append-4kto720p.mov"

  # Create a temporary list file for concatenation
  concat_file="$COMPRESSED_SAVE_DIR/file-list.txt"
  echo "file '$prepend_file'" > "$concat_file"
  echo "file '$source_file'" >> "$concat_file"

  # Generate concatenated output filename
  concat_output_file="$COMPRESSED_SAVE_DIR/${name}-ytready.${extension}"
  if [[ ! -f "$concat_output_file" ]]; then
    echo "Concatenating to $concat_output_file"
    ffmpeg -loglevel error -hide_banner -nostats -f concat -safe 0 -i "$concat_file" -c copy "$concat_output_file"
  else
    echo "Screened file already exists: $concat_output_file"
  fi

  # Clean up the temporary file list
  rm -f "$concat_file"

  # Move ytready files to rolling-compressed-ns-prefix-upload
  if [[ -f "$concat_output_file" ]]; then
    ytready_dest="$YTREADY_UPLOAD_DIR/$(basename "$concat_output_file")"
    echo "Moving ytready file to rolling-compressed-ns-prefix-upload: $concat_output_file"
    mv "$concat_output_file" "$ytready_dest"
  fi

  # Clean up the nosound file
  if [[ -f "$ns_output_file" ]]; then
    rm -f "$ns_output_file"
  fi

done

echo "All tasks completed successfully!"
