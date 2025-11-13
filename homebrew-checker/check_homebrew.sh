#!/bin/bash

# Parse command-line arguments
HIDE_UNSUPPORTED=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --hide-unsupported|-u)
            HIDE_UNSUPPORTED=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -u, --hide-unsupported    Hide apps that are not supported by Homebrew"
            echo "  -h, --help                Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

echo "Building Homebrew package cache..." >&2

# Get list of Homebrew-installed items (formulae + casks)
HOMEBREW_INSTALLED=$(brew list --formula --cask 2>/dev/null | tr '[:upper:]' '[:lower:]')

# Get list of ALL available Homebrew packages
HOMEBREW_AVAILABLE=$(brew search --formula --cask 2>/dev/null | tr '[:upper:]' '[:lower:]')

# Build a list of all app paths that Homebrew installed
# Format: store as space-separated list for compatibility with bash 3.2
echo "Mapping installed casks to their apps..." >&2
HOMEBREW_INSTALLED_APP_PATHS=""
HOMEBREW_INSTALLED_APP_NAMES=""

while IFS= read -r cask; do
    if [ -n "$cask" ]; then
        # Get the app name(s) that this cask installs
        # brew info --cask can show apps in multiple formats:
        # - "AppName.app (App)" in Artifacts section
        # - "/Applications/AppName.app" in paths
        # - Just "AppName.app" in some cases
        # - "AppName.pkg (Pkg)" for package installers
        
        # Method 1: Look for app artifacts (most reliable)
        app_artifacts=$(brew info --cask "$cask" 2>/dev/null | grep -E "\.app\s*\(App\)" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*(App).*//')
        
        # Method 2: Look for /Applications or ~/Applications paths
        # Extract full app paths (e.g., /Applications/AppName.app or ~/Applications/AppName.app)
        app_full_paths=$(brew info --cask "$cask" 2>/dev/null | grep -E "^\s*(/Applications|~/Applications)/.*\.app" | sed 's|^[[:space:]]*||' | sed 's|/Contents/.*||' | sed 's|\.app$|.app|')
        
        # Method 3: Handle .pkg installers - try to match cask name to app name
        # When a cask installs a .pkg, the app name might match the cask name when normalized
        has_pkg=$(brew info --cask "$cask" 2>/dev/null | grep -E "\.pkg\s*\(Pkg\)")
        if [ -n "$has_pkg" ] && [ -z "$app_artifacts" ] && [ -z "$app_full_paths" ]; then
            # Try to find an app that matches the cask name
            # Normalize cask name: "google-drive" -> "google drive"
            cask_normalized_to_app=$(echo "$cask" | tr '-' ' ' | tr '[:upper:]' '[:lower:]')
            # Try to find matching app in /Applications
            for app_dir in /Applications ~/Applications; do
                if [ -d "$app_dir" ]; then
                    for potential_app in "$app_dir"/*.app; do
                        if [ -d "$potential_app" ]; then
                            potential_name=$(basename "$potential_app" .app | tr '[:upper:]' '[:lower:]')
                            # Check if app name matches cask name (normalized)
                            if [ "$potential_name" = "$cask_normalized_to_app" ]; then
                                app_artifacts="${app_artifacts}${app_artifacts:+$'\n'}$(basename "$potential_app")"
                                break 2  # Break out of both loops
                            fi
                        fi
                    done
                fi
            done
        fi
        
        # Combine both methods - use artifacts first, then paths
        all_apps=$(echo -e "${app_artifacts}\n${app_full_paths}" | grep -v '^$' | sort -u)
        
        while IFS= read -r app_line; do
            if [ -n "$app_line" ]; then
                # Check if this is a full path or just an app name
                if [[ "$app_line" == *"/Applications/"* ]] || [[ "$app_line" == *"~/Applications/"* ]]; then
                    # It's a full path - expand ~ and normalize
                    app_path=$(echo "$app_line" | sed "s|^~|$HOME|")
                    # Keep original case for path, but lowercase for name matching
                    app_name_original=$(basename "$app_path" .app)
                    app_name=$(echo "$app_name_original" | tr '[:upper:]' '[:lower:]')
                else
                    # It's just an app name from artifacts - preserve original case
                    app_name_original=$(echo "$app_line" | sed 's|\.app.*||')
                    app_name=$(echo "$app_name_original" | tr '[:upper:]' '[:lower:]')
                    # Try to find the actual app with original case - check both locations
                    if [ -d "/Applications/${app_name_original}.app" ]; then
                        app_path="/Applications/${app_name_original}.app"
                    elif [ -d "$HOME/Applications/${app_name_original}.app" ]; then
                        app_path="$HOME/Applications/${app_name_original}.app"
                    else
                        # Try case-insensitive search in /Applications
                        found_path=$(find /Applications -maxdepth 1 -iname "${app_name_original}.app" -type d 2>/dev/null | head -1)
                        if [ -n "$found_path" ]; then
                            app_path="$found_path"
                        else
                            # Try case-insensitive search in ~/Applications
                            found_path=$(find "$HOME/Applications" -maxdepth 1 -iname "${app_name_original}.app" -type d 2>/dev/null | head -1)
                            if [ -n "$found_path" ]; then
                                app_path="$found_path"
                            else
                                # Default to /Applications (most common) - but this might not exist
                                app_path="/Applications/${app_name_original}.app"
                            fi
                        fi
                    fi
                fi
                
                if [ -n "$app_name" ] && [ -n "$app_path" ]; then
                    # Store app name (lowercase for matching) and path (original case for actual file system)
                    if [ -z "$HOMEBREW_INSTALLED_APP_NAMES" ]; then
                        HOMEBREW_INSTALLED_APP_NAMES="$app_name"
                        HOMEBREW_INSTALLED_APP_PATHS="$app_path"
                    else
                        HOMEBREW_INSTALLED_APP_NAMES="${HOMEBREW_INSTALLED_APP_NAMES} ${app_name}"
                        HOMEBREW_INSTALLED_APP_PATHS="${HOMEBREW_INSTALLED_APP_PATHS} $app_path"
                    fi
                fi
            fi
        done <<< "$all_apps"
    fi
done < <(brew list --cask 2>/dev/null)

# Function to normalize app name to potential Homebrew formula name
# Converts: "Visual Studio Code" -> "visual-studio-code"
normalize_to_homebrew_name() {
    local name="$1"
    # Convert to lowercase
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    # Replace spaces with hyphens
    name=$(echo "$name" | tr ' ' '-')
    # Remove special characters (keep alphanumeric and hyphens)
    name=$(echo "$name" | sed 's/[^a-z0-9-]//g')
    # Remove multiple consecutive hyphens
    name=$(echo "$name" | sed 's/-\+/-/g')
    # Remove leading/trailing hyphens
    name=$(echo "$name" | sed 's/^-\|-$//g')
    echo "$name"
}

# Function to check if app is Homebrew-installed
is_installed() {
    local app_basename="$1"
    local app_path="$2"  # Full path to the app for direct checking
    
    # Method 1: Direct check - see if this exact app path is in our Homebrew-installed list
    # This is the most reliable method
    # Normalize paths (expand ~, resolve to absolute path)
    if [ -n "$app_path" ] && [ -n "$HOMEBREW_INSTALLED_APP_PATHS" ]; then
        # Normalize the input path
        normalized_app_path=$(echo "$app_path" | sed "s|^~|$HOME|")
        # Resolve to absolute path if it exists
        if [ -e "$normalized_app_path" ]; then
            normalized_app_path=$(cd "$(dirname "$normalized_app_path")" && pwd)/$(basename "$normalized_app_path")
        fi
        
        for installed_path in $HOMEBREW_INSTALLED_APP_PATHS; do
            # Normalize the stored path
            normalized_installed=$(echo "$installed_path" | sed "s|^~|$HOME|")
            if [ -e "$normalized_installed" ]; then
                normalized_installed=$(cd "$(dirname "$normalized_installed")" && pwd)/$(basename "$normalized_installed")
            fi
            
            if [ "$normalized_app_path" = "$normalized_installed" ]; then
                echo "true"
                return
            fi
        done
    fi
    
    # Method 2: Check if app name is in our Homebrew-installed app names list
    if [ -n "$HOMEBREW_INSTALLED_APP_NAMES" ]; then
        for installed_name in $HOMEBREW_INSTALLED_APP_NAMES; do
            if [ "$app_basename" = "$installed_name" ]; then
                echo "true"
                return
            fi
        done
    fi
    
    # Method 3: Check normalized version in app names list
    local normalized=$(normalize_to_homebrew_name "$app_basename")
    if [ -n "$HOMEBREW_INSTALLED_APP_NAMES" ]; then
        for installed_name in $HOMEBREW_INSTALLED_APP_NAMES; do
            if [ "$normalized" = "$installed_name" ]; then
                echo "true"
                return
            fi
        done
    fi
    
    # Method 4: Direct cask check - iterate through all installed casks and check if they install this app
    # This is a fallback that queries Homebrew directly for the specific app
    for cask in $(brew list --cask 2>/dev/null); do
        if [ -z "$cask" ]; then
            continue
        fi
        
        # Check if this cask installs the app (check both artifact format and path format)
        cask_info=$(brew info --cask "$cask" 2>/dev/null)
        
        # Extract app names from cask info using the same method as mapping phase
        # Method 4a: Look for app artifacts (most reliable)
        app_artifacts=$(echo "$cask_info" | grep -E "\.app\s*\(App\)" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*(App).*//')
        
        # Method 4b: Look for /Applications or ~/Applications paths
        app_full_paths=$(echo "$cask_info" | grep -E "^\s*(/Applications|~/Applications)/.*\.app" | sed 's|^[[:space:]]*||' | sed 's|/Contents/.*||' | sed 's|\.app$|.app|')
        
        # Method 4c: Handle .pkg installers - check if cask name matches app name
        has_pkg=$(echo "$cask_info" | grep -E "\.pkg\s*\(Pkg\)")
        if [ -n "$has_pkg" ] && [ -z "$app_artifacts" ] && [ -z "$app_full_paths" ]; then
            # Normalize cask name and compare with app name
            cask_normalized_to_app=$(echo "$cask" | tr '-' ' ' | tr '[:upper:]' '[:lower:]')
            if [ "$cask_normalized_to_app" = "$app_basename" ]; then
                echo "true"
                return
            fi
        fi
        
        # Combine both methods
        cask_apps=$(echo -e "${app_artifacts}\n${app_full_paths}" | grep -v '^$' | sort -u)
        
        while IFS= read -r cask_app_line; do
            if [ -n "$cask_app_line" ]; then
                # Extract app name from this line (handle both paths and app names)
                if [[ "$cask_app_line" == *"/Applications/"* ]] || [[ "$cask_app_line" == *"~/Applications/"* ]]; then
                    # It's a full path
                    cask_app_path=$(echo "$cask_app_line" | sed "s|^~|$HOME|")
                    cask_app_name=$(basename "$cask_app_path" .app | tr '[:upper:]' '[:lower:]')
                else
                    # It's just an app name from artifacts
                    cask_app_name=$(echo "$cask_app_line" | sed 's|\.app.*||' | tr '[:upper:]' '[:lower:]')
                fi
                
                # Compare extracted app name (case-insensitive) with what we're looking for
                if [ "$cask_app_name" = "$app_basename" ]; then
                    echo "true"
                    return
                fi
                
                # Also check normalized version
                cask_app_normalized=$(normalize_to_homebrew_name "$cask_app_name")
                if [ "$cask_app_normalized" = "$normalized" ] || [ "$cask_app_name" = "$normalized" ]; then
                    echo "true"
                    return
                fi
                
                # Check if actual app path matches
                if [ -n "$app_path" ]; then
                    if [[ "$cask_app_line" == *"/Applications/"* ]] || [[ "$cask_app_line" == *"~/Applications/"* ]]; then
                        cask_app_path=$(echo "$cask_app_line" | sed "s|^~|$HOME|")
                        # Normalize both paths for comparison
                        normalized_cask_path=$(echo "$cask_app_path" | sed "s|^~|$HOME|")
                        normalized_app_path=$(echo "$app_path" | sed "s|^~|$HOME|")
                        if [ -e "$normalized_cask_path" ] && [ -e "$normalized_app_path" ]; then
                            # Resolve to absolute paths
                            abs_cask_path=$(cd "$(dirname "$normalized_cask_path")" && pwd)/$(basename "$normalized_cask_path")
                            abs_app_path=$(cd "$(dirname "$normalized_app_path")" && pwd)/$(basename "$normalized_app_path")
                            if [ "$abs_cask_path" = "$abs_app_path" ]; then
                                echo "true"
                                return
                            fi
                        fi
                    fi
                fi
            fi
        done <<< "$cask_apps"
    done
    
    # Method 5: Check exact match in installed packages list
    if echo "$HOMEBREW_INSTALLED" | grep -q "^${app_basename}$"; then
        echo "true"
        return
    fi
    
    # Method 6: Check normalized version in installed packages list
    if echo "$HOMEBREW_INSTALLED" | grep -q "^${normalized}$"; then
        echo "true"
        return
    fi
    
    # Method 7: Check if any installed package contains the app name (partial match)
    if echo "$HOMEBREW_INSTALLED" | grep -q "${app_basename}"; then
        echo "true"
        return
    fi
    
    # Method 8: Check normalized partial match
    if echo "$HOMEBREW_INSTALLED" | grep -q "${normalized}"; then
        echo "true"
        return
    fi
    
    echo "false"
}

# Function to check if app is available/supported in Homebrew
is_supported() {
    local app_basename="$1"
    local normalized=$(normalize_to_homebrew_name "$app_basename")
    
    # Method 1: Check exact match in available packages
    if echo "$HOMEBREW_AVAILABLE" | grep -q "^${app_basename}$"; then
        echo "true"
        return
    fi
    
    # Method 2: Check normalized version (spaces -> hyphens)
    if echo "$HOMEBREW_AVAILABLE" | grep -q "^${normalized}$"; then
        echo "true"
        return
    fi
    
    # Method 3: Check partial match in available packages
    if echo "$HOMEBREW_AVAILABLE" | grep -q "${app_basename}"; then
        echo "true"
        return
    fi
    
    # Method 4: Active search using brew search (for exact/normalized name)
    if brew search --formula --cask "$app_basename" 2>/dev/null | grep -qi "^${app_basename}$"; then
        echo "true"
        return
    fi
    
    if brew search --formula --cask "$normalized" 2>/dev/null | grep -qi "^${normalized}$"; then
        echo "true"
        return
    fi
    
    # Method 5: Search in descriptions (case-insensitive)
    if brew search --desc --formula --cask "$app_basename" 2>/dev/null | grep -qi "${app_basename}"; then
        echo "true"
        return
    fi
    
    # Method 6: Try without spaces (e.g., "visualstudiocode")
    local no_spaces=$(echo "$app_basename" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    if echo "$HOMEBREW_AVAILABLE" | grep -q "^${no_spaces}$"; then
        echo "true"
        return
    fi
    
    echo "false"
}

# Function to check if app is a macOS system app
is_system_app() {
    local app_path="$1"
    local app_basename_lower="$2"
    
    # Method 1: Check if app is in system directories
    # System apps are typically in /System/Applications, /System/Library/CoreServices, etc.
    if [[ "$app_path" == /System/* ]]; then
        echo "true"
        return
    fi
    
    # Method 2: Check bundle identifier (most reliable)
    # System apps have com.apple.* bundle identifiers
    if [ -f "$app_path/Contents/Info.plist" ]; then
        bundle_id=$(defaults read "$app_path/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)
        if [[ "$bundle_id" == com.apple.* ]]; then
            echo "true"
            return
        fi
    fi
    
    # Method 3: Check file ownership
    # System apps are typically owned by root or _system
    if [ -d "$app_path" ]; then
        owner=$(stat -f "%Su" "$app_path" 2>/dev/null)
        if [ "$owner" = "root" ] || [ "$owner" = "_system" ]; then
            if [[ "$app_path" == /Applications/* ]]; then
                bundle_id=$(defaults read "$app_path/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)
                if [[ "$bundle_id" == com.apple.* ]]; then
                    echo "true"
                    return
                fi
            fi
        fi
    fi
    
    # Method 4: Known system apps list (common macOS apps in /Applications)
    case "$app_basename_lower" in
        safari|pages|numbers|keynote|"quicktime player"|"system preferences"|"system settings"|"app store"|"time machine"|"disk utility"|terminal|"activity monitor"|console|"font book"|"image capture"|"photo booth"|preview|textedit|calculator|calendar|contacts|dictionary|"find my"|mail|maps|messages|music|news|notes|photos|podcasts|reminders|shortcuts|stickies|tv|"voice memos"|books|chess|home|stocks|weather|"automator"|"bluetooth file exchange"|"color sync utility"|"digital color meter"|"grapher"|"keychain access"|"migration assistant"|"network utility"|"script editor"|"system information"|"wireless diagnostics"|"airport utility"|"audio midi setup"|"boot camp assistant"|"java preferences"|"raid utility"|"x11")
            echo "true"
            return
            ;;
    esac
    
    echo "false"
}

echo "Checking applications..." >&2

# Collect all results first
declare -a app_names
declare -a installed_results
declare -a supported_results

# Main loop through /Applications and ~/Applications
for app_dir in /Applications ~/Applications; do
    if [ -d "$app_dir" ]; then
        for app_path in "$app_dir"/*.app; do
            if [ -d "$app_path" ]; then
                app_name=$(basename "$app_path")
                app_basename="${app_name%.app}"  # Remove .app extension
                app_basename_lower=$(echo "$app_basename" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
                
                if [ "$(is_system_app "$app_path" "$app_basename_lower")" = "true" ]; then
                    continue
                fi

                case "$app_basename_lower" in
                    "google sheets"|"google docs"|"google slides")
                        continue
                        ;;
                esac

                is_installed_result=$(is_installed "$app_basename_lower" "$app_path")
                is_supported_result=$(is_supported "$app_basename_lower")
                
                app_names+=("$app_name")
                installed_results+=("$is_installed_result")
                supported_results+=("${is_supported_result}")
            fi
        done
    fi
done

# Sort the arrays together (by app name)
# Create indices array and sort
indices=($(seq 0 $((${#app_names[@]} - 1)) | sort -k1,1 -t$'\t' --key=1,1))
sorted_indices=($(for i in "${indices[@]}"; do echo "$i"; done | awk -v apps="${app_names[*]}" 'BEGIN{split(apps, a, " ")} {print $1, a[$1+1]}' | sort -k2,2 | awk '{print $1}'))

# Print table header
printf "%-50s %-30s %-30s\n" "Application" "Supported by Homebrew?" "Installed by Homebrew?"
printf "%-50s %-30s %-30s\n" "$(printf '=%.0s' {1..50})" "$(printf '=%.0s' {1..30})" "$(printf '=%.0s' {1..30})"

# Print table rows
for i in "${!app_names[@]}"; do
    # Skip apps that are not supported if flag is set
    if [ "$HIDE_UNSUPPORTED" = "true" ] && [ "${supported_results[$i]}" != "true" ]; then
        continue
    fi
    printf "%-50s %-30s %-30s\n" "${app_names[$i]}" "${supported_results[$i]}" "${installed_results[$i]}"
done | sort -k1,1
