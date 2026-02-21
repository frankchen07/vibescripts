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
echo ""
echo "=== Step 1: Compressing video files ==="
shopt -s nullglob
mov_files=("$DIR"/*.mov)

if [ ${#mov_files[@]} -eq 0 ]; then
  echo "No .mov files found in $DIR"
  exit 1
fi

# Filter out excluded files
filtered_files=()
for file in "${mov_files[@]}"; do
  filename=$(basename -- "$file")
  if [[ "$filename" != "10p-append-4kto720p.mov" ]]; then
    filtered_files+=("$file")
  fi
done

if [ ${#filtered_files[@]} -eq 0 ]; then
  echo "No files to process (all files excluded)."
  exit 1
fi

echo "Found ${#filtered_files[@]} file(s) to process..."
echo ""

for input_file in "${filtered_files[@]}"; do
  filename=$(basename -- "$input_file")
  extension="${filename##*.}"
  name="${filename%.*}"

  # Check if file is valid before processing
  echo "Checking validity: $filename"
  if ! check_video_valid "$input_file"; then
    echo "ERROR: $filename appears to be corrupted or incomplete. Skipping."
    echo ""
    continue
  fi

  # Create compressed file
  compressed_file="$DIR/${name}-compressed.${extension}"
  if [[ ! -f "$compressed_file" ]]; then
    echo "Compressing: $filename -> ${name}-compressed.${extension}"
    
    # Build ffmpeg command with conditional high profile option
    ffmpeg_cmd=(
      ffmpeg -loglevel error -hide_banner -nostats -i "$input_file"
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
    
    if ! "${ffmpeg_cmd[@]}"; then
      echo "ERROR: Failed to compress $filename"
      rm -f "$compressed_file"  # Remove partial file if compression failed
      echo ""
      continue
    fi
    echo "✓ Compression complete: ${name}-compressed.${extension}"
  else
    echo "Compressed file already exists: ${name}-compressed.${extension}"
  fi
  echo ""
done

# Step 2: Move compressed files to teaching-compressed and trash originals
echo ""
echo "=== Step 2: Moving compressed files to teaching-compressed and trashing originals ==="
shopt -s nullglob
compressed_files=("$DIR"/*-compressed.mov)

if [ ${#compressed_files[@]} -eq 0 ]; then
  echo "No compressed files found to move."
else
  echo "Processing ${#compressed_files[@]} compressed file(s)..."
  echo ""
fi

for compressed_file in "${compressed_files[@]}"; do
    # Validate the compressed file before proceeding
    filename=$(basename -- "$compressed_file")
    echo "Validating: $filename"
    if ! check_video_valid "$compressed_file"; then
        echo "ERROR: $filename is invalid or corrupted. Skipping to preserve original."
        rm -f "$compressed_file"  # Remove the bad compressed file
        echo ""
        continue
    fi
    
    # Check that the file has actual content (not empty)
    if [[ ! -s "$compressed_file" ]]; then
        echo "ERROR: $filename is empty. Skipping to preserve original."
        rm -f "$compressed_file"  # Remove the empty file
        echo ""
        continue
    fi
    
    # Generate the original filename by removing "-compressed"
    original_file="${compressed_file//-compressed/}"
    original_filename=$(basename -- "$original_file")
    final_dest="$TEACHING_COMPRESSED_DIR/$original_filename"
    
    # Handle case where original is already in output directory
    if [[ -f "$final_dest" ]]; then
        # Original is in output directory - trash it first, then replace with compressed
        echo "Replacing existing file in teaching-compressed: $original_filename"
        echo "Moving original to trash: $original_filename"
        trash "$final_dest"
        echo "Moving compressed file: $filename -> $original_filename"
        mv "$compressed_file" "$final_dest"
        echo "✓ File replaced successfully"
    else
        # Normal case: move compressed file to output directory
        echo "Moving compressed file to teaching-compressed: $filename -> $original_filename"
        mv "$compressed_file" "$final_dest"
        
        # Move original file to trash if it exists (and is different from final_dest)
        if [[ -f "$original_file" && "$original_file" != "$final_dest" ]]; then
            echo "Moving original to trash: $(basename "$original_file")"
            trash "$original_file"
        fi
        echo "✓ File moved successfully"
    fi
    echo ""
done

echo ""
echo "All tasks completed successfully!"