#!/bin/bash

# Directory to process (default is the current directory)
DIR=${1:-.}
# Get the script's directory for output directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define output directories (in processing-jj folder)
COMPRESSED_SAVE_DIR="$SCRIPT_DIR/rolling-compressed"
YTREADY_UPLOAD_DIR="$SCRIPT_DIR/rolling-ytready"

# Create output directories if they don't exist, or verify they exist
if [[ -d "$COMPRESSED_SAVE_DIR" ]]; then
    echo "Using existing directory: $COMPRESSED_SAVE_DIR"
else
    mkdir -p "$COMPRESSED_SAVE_DIR" && echo "Created directory: $COMPRESSED_SAVE_DIR"
fi

if [[ -d "$YTREADY_UPLOAD_DIR" ]]; then
    echo "Using existing directory: $YTREADY_UPLOAD_DIR"
else
    mkdir -p "$YTREADY_UPLOAD_DIR" && echo "Created directory: $YTREADY_UPLOAD_DIR"
fi

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

# Step 2: Move compressed files to rolling-compressed and trash originals
for compressed_file in "$DIR"/*-compressed.mov; do
    if [[ -f "$compressed_file" ]]; then
        # Get the original filename (without -compressed suffix)
        original_file="${compressed_file//-compressed/}"
        original_filename=$(basename -- "$original_file")
        
        # Move compressed file to rolling-compressed
        compressed_dest="$COMPRESSED_SAVE_DIR/$(basename "$compressed_file")"
        final_dest="$COMPRESSED_SAVE_DIR/$original_filename"
        
        if [[ ! -f "$final_dest" ]]; then
            echo "Moving compressed file to rolling-compressed: $compressed_file"
            mv "$compressed_file" "$compressed_dest"
            
            # Rename to remove -compressed suffix
            echo "Renaming to remove -compressed suffix: $compressed_dest -> $final_dest"
            mv "$compressed_dest" "$final_dest"
        else
            echo "File already exists in rolling-compressed: $final_dest"
            rm -f "$compressed_file"  # Remove duplicate
        fi
        
        # Trash the original file if it exists
        if [[ -f "$original_file" ]]; then
            echo "Moving original to trash: $original_file"
            trash "$original_file"
        fi
    fi
done

# Rename any existing -compressed.mov files in rolling-compressed (for backward compatibility)
echo ""
echo "Renaming any existing -compressed files in rolling-compressed..."
for old_file in "$COMPRESSED_SAVE_DIR"/*-compressed.mov; do
    if [[ -f "$old_file" ]]; then
        new_file="${old_file//-compressed/}"
        if [[ ! -f "$new_file" ]]; then
            echo "Renaming existing file: $(basename "$old_file") -> $(basename "$new_file")"
            mv "$old_file" "$new_file"
        else
            echo "File already exists (non-compressed version): $(basename "$new_file"), removing duplicate"
            rm -f "$old_file"
        fi
    fi
done

# Step 3: Process compressed files from rolling-compressed
echo ""
echo "=== Step 3: Processing compressed files ==="
shopt -s nullglob
# Process all .mov files except ones with special suffixes
mov_files=("$COMPRESSED_SAVE_DIR"/*.mov)
# Filter out files with -originalnosound or -ytready suffixes
filtered_files=()
for file in "${mov_files[@]}"; do
    filename=$(basename -- "$file")
    # Skip files with special suffixes
    if [[ "$filename" != *"-originalnosound."* ]] && [[ "$filename" != *"-ytready."* ]] && [[ "$filename" != *"-compressed."* ]]; then
        # Also skip the prepend file if it somehow got in there
        if [[ "$filename" != "10p-append-4kto720p.mov" ]]; then
            filtered_files+=("$file")
        fi
    fi
done

if [ ${#filtered_files[@]} -eq 0 ]; then
  echo "No compressed files found in rolling-compressed directory."
  echo "Run the script with .mov files in the current directory to compress them first."
  exit 1
fi

echo "Processing ${#filtered_files[@]} compressed file(s)..."

for input_file in "${filtered_files[@]}"; do
  # Skip specific files
  if [[ "$input_file" == *"/10p-append-4kto720p.mov" ]]; then
    echo "Skipping $input_file: Excluded file."
    continue
  fi

  filename=$(basename -- "$input_file")
  extension="${filename##*.}"
  name="${filename%.*}"

  # Check if this file has already been fully processed
  expected_ytready="$YTREADY_UPLOAD_DIR/${name}-ytready.${extension}"
  if [[ -f "$expected_ytready" ]]; then
    echo "Skipping $input_file: Already fully processed (ytready file exists)."
    continue
  fi

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
  
  # Convert prepend_file to absolute path for concat file list
  if [[ ! "$prepend_file" = /* ]]; then
    prepend_file="$(cd "$DIR" && pwd)/10p-append-4kto720p.mov"
  fi
  
  # Convert source_file to absolute path as well
  if [[ ! "$source_file" = /* ]]; then
    source_file="$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")"
  fi

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

  # Move ytready files to rolling-ytready
  if [[ -f "$concat_output_file" ]]; then
    ytready_dest="$YTREADY_UPLOAD_DIR/$(basename "$concat_output_file")"
    if [[ ! -f "$ytready_dest" ]]; then
        echo "Moving ytready file to rolling-ytready: $concat_output_file"
        mv "$concat_output_file" "$ytready_dest"
    else
        echo "Ytready file already exists in rolling-ytready: $ytready_dest"
        rm -f "$concat_output_file"  # Remove duplicate
    fi
  fi

  # Clean up the nosound file
  if [[ -f "$ns_output_file" ]]; then
    rm -f "$ns_output_file"
  fi

done

echo ""
echo "All tasks completed successfully!"
