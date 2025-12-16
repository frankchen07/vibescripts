#!/bin/bash

# Parse arguments
USE_HIGH_PROFILE=false
DIR="."

for arg in "$@"; do
  case $arg in
    --high|-h)
      USE_HIGH_PROFILE=true
      shift
      ;;
    *)
      if [[ -d "$arg" ]]; then
        DIR="$arg"
      fi
      ;;
  esac
done

# Default to current directory if no directory specified
DIR=${DIR:-.}
# Get the script's directory for output directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define output directory (in processing-jj folder)
TEACHING_COMPRESSED_DIR="$SCRIPT_DIR/teaching-compressed"

# Create output directory if it doesn't exist, or verify it exists
if [[ -d "$TEACHING_COMPRESSED_DIR" ]]; then
    echo "Using existing directory: $TEACHING_COMPRESSED_DIR"
else
    mkdir -p "$TEACHING_COMPRESSED_DIR" && echo "Created directory: $TEACHING_COMPRESSED_DIR"
fi

# Ensure necessary tools are available
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is not installed. Exiting." >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe is not installed. Exiting." >&2; exit 1; }
command -v trash >/dev/null 2>&1 || { echo "trash is not installed. Exiting." >&2; exit 1; }

# Function to check if a video file is valid
check_video_valid() {
    local file="$1"
    # Use ffprobe to check if file is valid (suppress output, only check exit code)
    ffprobe -v error -i "$file" >/dev/null 2>&1
    return $?
}

# Step 1: Compress files first
echo "=== Step 1: Compressing video files ==="
for input_file in "$DIR"/*.mov; do
  
  # Skip if no .mov files found (glob expansion)
  [[ ! -f "$input_file" ]] && continue
  
  # Skip specific files
  if [[ "$input_file" == *"/10p-append-4kto720p.mov" ]]; then
    echo "Skipping $input_file: Excluded file."
    continue
  fi

  # Check if file is valid before processing
  echo "Checking validity of: $input_file"
  if ! check_video_valid "$input_file"; then
    echo "ERROR: $input_file appears to be corrupted or incomplete. Skipping."
    continue
  fi

  filename=$(basename -- "$input_file")
  extension="${filename##*.}"
  name="${filename%.*}"

  # Create compressed file
  compressed_file="$DIR/${name}-compressed.${extension}"
  if [[ ! -f "$compressed_file" ]]; then
    echo "Compressing $input_file -> $compressed_file"
    
    # Build ffmpeg command with conditional high profile option
    ffmpeg_cmd=(
      ffmpeg -i "$input_file"
      -c:v libx264 -profile:v high -level 4.1 -preset veryfast -crf 23
      -vf "scale=1280:720,fps=30"
      -b:v 8083k
    )
    
    # Add pix_fmt only if --high flag is used
    if [[ "$USE_HIGH_PROFILE" == true ]]; then
      ffmpeg_cmd+=(-pix_fmt yuv420p)
    fi
    
    ffmpeg_cmd+=(
      -c:a aac -b:a 191k -ar 44100
      -movflags +faststart
      "$compressed_file"
    )
    
    if ! "${ffmpeg_cmd[@]}" 2>&1 | tee /tmp/ffmpeg_output.log; then
      echo "ERROR: Failed to compress $input_file. Check /tmp/ffmpeg_output.log for details."
      rm -f "$compressed_file"  # Remove partial file if compression failed
      continue
    fi
  else
    echo "Compressed file already exists: $compressed_file"
  fi
done

# Step 2: Move compressed files to teaching-compressed and trash originals
echo ""
echo "=== Step 2: Moving compressed files to teaching-compressed and trashing originals ==="
for compressed_file in "$DIR"/*-compressed.mov; do
    if [[ ! -f "$compressed_file" ]]; then
        continue
    fi
    
    # Validate the compressed file before proceeding
    echo "Validating compressed file: $compressed_file"
    if ! check_video_valid "$compressed_file"; then
        echo "ERROR: $compressed_file is invalid or corrupted. Skipping to preserve original."
        rm -f "$compressed_file"  # Remove the bad compressed file
        continue
    fi
    
    # Check that the file has actual content (not empty)
    if [[ ! -s "$compressed_file" ]]; then
        echo "ERROR: $compressed_file is empty. Skipping to preserve original."
        rm -f "$compressed_file"  # Remove the empty file
        continue
    fi
    
    # Generate the original filename by removing "-compressed"
    original_file="${compressed_file//-compressed/}"
    original_filename=$(basename -- "$original_file")
    final_dest="$TEACHING_COMPRESSED_DIR/$original_filename"
    
    # Move compressed file to teaching-compressed and rename to remove -compressed suffix
    if [[ ! -f "$final_dest" ]]; then
        echo "Moving compressed file to teaching-compressed: $compressed_file -> $final_dest"
        mv "$compressed_file" "$final_dest"
    else
        echo "File already exists in teaching-compressed: $final_dest"
        rm -f "$compressed_file"  # Remove duplicate
    fi
    
    # Move original file to trash if it exists
    if [[ -f "$original_file" ]]; then
        echo "Moving original to trash: $original_file"
        trash "$original_file"
    fi
done

echo ""
echo "All tasks completed successfully!"