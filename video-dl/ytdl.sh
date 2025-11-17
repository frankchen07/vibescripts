#!/bin/bash

# yt-dlp automated download script
# Usage: zscript_download.sh <youtube_url>

# Check if yt-dlp is installed
if ! command -v yt-dlp &> /dev/null; then
    echo "Error: yt-dlp not found. Install it with: brew install yt-dlp"
    exit 1
fi

# Check if URL is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <youtube_url>"
    echo "Example: $0 https://www.youtube.com/watch?v=-In1EPx9t8M"
    exit 1
fi

URL="$1"

# Extract YouTube video ID from URL
VIDEO_ID=$(echo "$URL" | sed -n 's/.*[?&]v=\([^&]*\).*/\1/p' | head -1)

# Get format list
echo "Fetching available formats..."
FORMAT_OUTPUT=$(yt-dlp -F "$URL" 2>&1 | grep -v -E "^\[(youtube|info|jsc)\]")

# Check if command succeeded
# Check exit status before filtering
TEMP_OUTPUT=$(yt-dlp -F "$URL" 2>&1)
EXIT_CODE=$?
FORMAT_OUTPUT=$(echo "$TEMP_OUTPUT" | grep -v -E "^\[(youtube|info|jsc)\]")

if [ $EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to fetch format list"
    echo "$TEMP_OUTPUT"
    exit 1
fi

# Get format list again (without verbose output)
FORMAT_OUTPUT=$(yt-dlp -F "$URL" 2>/dev/null)

# Check if command succeeded
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch format list"
    echo "$FORMAT_OUTPUT"
    exit 1
fi

# Print the table for reference
echo ""
if [ -n "$VIDEO_ID" ]; then
    echo "Curated formats for $VIDEO_ID:"
else
    echo "Available formats:"
fi
echo "=================="
echo "$FORMAT_OUTPUT"
echo ""

# Parse audio format: m4a, medium/high, prefer English/default if available, highest TBR
# Exclude DRC, prefer English/default, then fall back to any medium/high
AUDIO_LINE=$(echo "$FORMAT_OUTPUT" | awk '
    /audio only/ && /m4a/ && (/medium|high/) && !/drc/ && !/DRC/ {
        # Extract ID (first field)
        id = $1
        # Check if it is English and default (preferred)
        # Look for English variations: [en], [en-US], English, en-US, etc.
        is_preferred = 0
        if ((/\[en/ || /English/ || /en-US/ || /en /) && /default/) {
            is_preferred = 2
        } else if (/\[en/ || /English/ || /en-US/ || /en /) {
            is_preferred = 1
        }
        # Extract TBR (look for pattern like "129k" in the line)
        match($0, /[0-9]+k/)
        if (RSTART > 0) {
            tbr_str = substr($0, RSTART, RLENGTH-1)
            tbr = tbr_str + 0
            # Print: preference_score, tbr, id, full_line
            print is_preferred, tbr, id, $0
        }
    }
' | sort -k1 -rn -k2 -rn | head -1)

AUDIO_ID=$(echo "$AUDIO_LINE" | awk '{print $3}')
AUDIO_FULL_LINE=$(echo "$AUDIO_LINE" | awk '{$1=$2=$3=""; print substr($0, 4)}')

# Parse video format: mp4, video only, avc1 codec, highest resolution, highest TBR
# Store both ID and full line
VIDEO_LINE=$(echo "$FORMAT_OUTPUT" | awk '
    /video only/ && /mp4/ && /avc1/ {
        # Extract ID (first field)
        id = $1
        # Extract resolution (e.g., 1920x1080) - look for pattern like "NNNNxNNNN"
        match($0, /[0-9]+x[0-9]+/)
        if (RSTART > 0) {
            res_str = substr($0, RSTART, RLENGTH)
            # Extract height (second number)
            split(res_str, res_parts, "x")
            height = res_parts[2] + 0
            # Extract TBR
            match($0, /[0-9]+k/)
            if (RSTART > 0) {
                tbr_str = substr($0, RSTART, RLENGTH-1)
                tbr = tbr_str + 0
                print id, height, tbr, $0
            }
        }
    }
' | sort -k2 -rn -k3 -rn | head -1)

VIDEO_ID=$(echo "$VIDEO_LINE" | awk '{print $1}')
VIDEO_FULL_LINE=$(echo "$VIDEO_LINE" | awk '{$1=$2=$3=""; print substr($0, 4)}')

# Check if we found both formats
if [ -z "$AUDIO_ID" ]; then
    echo "Error: Could not find suitable audio format (m4a, medium/high)"
    exit 1
fi

if [ -z "$VIDEO_ID" ]; then
    echo "Error: Could not find suitable video format (mp4, avc1 codec)"
    exit 1
fi

# Combine format IDs
FORMAT_STRING="${AUDIO_ID}+${VIDEO_ID}"

# Extract the actual rows from the format table for the selected IDs
AUDIO_ROW=$(echo "$FORMAT_OUTPUT" | grep -E "^${AUDIO_ID}[[:space:]]" | head -1)
VIDEO_ROW=$(echo "$FORMAT_OUTPUT" | grep -E "^${VIDEO_ID}[[:space:]]" | head -1)

echo "We're using: $FORMAT_STRING"
echo ""
echo "Selected format rows:"
echo "====================="
echo "$AUDIO_ROW"
echo "$VIDEO_ROW"
echo ""

# Ask for confirmation
while true; do
    read -p "Continue with download? (Y/n): " -n 1 -r
    echo ""
    case $REPLY in
        [Yy]|"")
            echo ""
            echo "Starting download..."
            echo ""
            break
            ;;
        [Nn])
            echo "Download cancelled."
            exit 0
            ;;
        *)
            echo "Please enter Y or N"
            ;;
    esac
done

# Download the video
yt-dlp --continue --retries 10 --fragment-retries 10 --merge-output-format mp4 --no-check-certificate -f "$FORMAT_STRING" -P "$HOME/Downloads" "$URL"

if [ $? -eq 0 ]; then
    echo ""
    echo "Download complete!"
else
    echo ""
    echo "Download failed. Check the format table above for manual selection."
    exit 1
fi