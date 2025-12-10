#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define directories relative to script location
COMPRESSED_SAVE_DIR="$SCRIPT_DIR/rolling-compressed-save"
YTREADY_UPLOAD_DIR="$SCRIPT_DIR/rolling-compressed-nsprefix-upload-del"
prepend_file="$SCRIPT_DIR/10p-append-4kto720p.mov"

# Create output directory if it doesn't exist
mkdir -p "$YTREADY_UPLOAD_DIR"

# Ensure necessary tools are available
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is not installed. Exiting." >&2; exit 1; }

# Check if rolling-compressed-save directory exists
if [[ ! -d "$COMPRESSED_SAVE_DIR" ]]; then
  echo "Error: rolling-compressed-save directory not found at $COMPRESSED_SAVE_DIR"
  exit 1
fi

# Check if prepend file exists
if [[ ! -f "$prepend_file" ]]; then
  echo "Error: 10p-append-4kto720p.mov not found at $prepend_file"
  exit 1
fi

# Process compressed files from rolling-compressed-save
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

  # Skip files that already have -originalnosound or -ytready suffix
  if [[ "$input_file" == *"-originalnosound.mov" ]] || [[ "$input_file" == *"-ytready.mov" ]]; then
    echo "Skipping $input_file: Already processed."
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