#!/bin/bash

# Cache Cleaner Script
# Usage: cleanup [--spotify] [quicktime] [whatsapp] [telegram]
#        cleanup --find [app_name]  (to find cache locations)

# Function to move cache to trash
clean_cache() {
    local cache_path="$1"
    local app_name="$2"
    
    if [ -e "$cache_path" ]; then
        echo "Cleaning $app_name cache: $cache_path"
        trash "$cache_path"
        echo "✓ Moved to trash"
    else
        echo "⚠ Cache not found: $cache_path"
    fi
}

# Function to find cache locations
find_caches() {
    local app_name="$1"
    echo "Searching for $app_name cache locations..."
    echo ""
    
    # Search in Containers
    echo "Checking ~/Library/Containers/..."
    find "$HOME/Library/Containers" -maxdepth 3 -type d -iname "*${app_name}*" 2>/dev/null | head -10
    
    # Search in Caches
    echo ""
    echo "Checking ~/Library/Caches/..."
    find "$HOME/Library/Caches" -maxdepth 2 -type d -iname "*${app_name}*" 2>/dev/null | head -10
    
    # Search in Application Support
    echo ""
    echo "Checking ~/Library/Application Support/..."
    find "$HOME/Library/Application Support" -maxdepth 2 -type d -iname "*${app_name}*" 2>/dev/null | head -10
}

# Define cache locations for each app
clean_spotify() {
    echo "Cleaning Spotify caches..."
    clean_cache "$HOME/Library/Caches/com.spotify.client/Data" "Spotify (Data)"
    clean_cache "$HOME/Library/Application Support/Spotify/PersistentCache/Storage" "Spotify (Storage)"
}

clean_quicktime() {
    echo "Cleaning QuickTime caches..."
    clean_cache "$HOME/Library/Containers/com.apple.QuickTimePlayerX/Data/Library/Autosave Information" "QuickTime"
}

clean_whatsapp() {
    echo "Cleaning WhatsApp caches..."
    # Main container cache location
    clean_cache "$HOME/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches" "WhatsApp"
}

clean_telegram() {
    echo "Cleaning Telegram caches..."
    # Main cache location (found in ~/Library/Caches/)
    clean_cache "$HOME/Library/Caches/ru.keepcoder.Telegram" "Telegram"
    # Also check container cache if it exists
    clean_cache "$HOME/Library/Containers/ru.keepcoder.Telegram/Data/Library/Caches" "Telegram (Container)"
}

# Check if trash command exists
if ! command -v trash &> /dev/null; then
    echo "Error: 'trash' command not found."
    echo "Install it with: brew install trash"
    exit 1
fi

# Handle --find mode
if [ "$1" = "--find" ]; then
    if [ -z "$2" ]; then
        echo "Usage: $0 --find [app_name]"
        echo "Example: $0 --find telegram"
        exit 1
    fi
    find_caches "$2"
    exit 0
fi

# Parse arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 [--spotify] [quicktime] [whatsapp] [telegram]"
    echo "       $0 --find [app_name]  (to find cache locations)"
    echo ""
    echo "Examples:"
    echo "  $0 --spotify quicktime whatsapp telegram"
    echo "  $0 spotify quicktime"
    echo "  $0 --find telegram"
    exit 1
fi

# Process each argument
for arg in "$@"; do
    # Remove -- prefix if present and convert to lowercase
    app=$(echo "$arg" | sed 's/^--//' | tr '[:upper:]' '[:lower:]')
    
    case "$app" in
        spotify)
            clean_spotify
            ;;
        quicktime|qt)
            clean_quicktime
            ;;
        whatsapp|wa)
            clean_whatsapp
            ;;
        telegram|tg)
            clean_telegram
            ;;
        *)
            echo "⚠ Unknown app: $arg (skipping)"
            ;;
    esac
done

echo ""
echo "Cache cleanup complete!"
