#!/bin/bash

# Initialize variables
OS_TYPE=""
VERBOSE=false
SHOW_LIST=false
backup_date=$(date +"_%d%b%Y-%I.%M%P")

# OS-specific directories
ProfileDirectoryLinux="$HOME/.mozilla/firefox"
ProfileDirectoryWin="$APPDATA/Mozilla/Firefox/Profiles/"
ProfileDirectoryMac="$HOME/.mozilla/firefox"

detect_os() {
    case "$(uname -s)" in
        Linux*)     OS_TYPE="linux" ;;
        Darwin*)    OS_TYPE="macos" ;;
        MINGW*|CYGWIN*|MSYS*) OS_TYPE="windows" ;;
        *)          OS_TYPE="unknown" ;;
    esac
}

# Detect OS and set directories
detect_os

case "$OS_TYPE" in
    linux)   ProfileDirectory="$ProfileDirectoryLinux" ;;
    windows) ProfileDirectory="$ProfileDirectoryWin" ;;
    macos)   ProfileDirectory="$ProfileDirectoryMac" ;;
    *)
        echo "Unsupported OS: $(uname -s)"
        exit 1
        ;;
esac

ProfileINI="$ProfileDirectory/profiles.ini"

# Verify critical paths exist
if [[ ! -f "$ProfileINI" ]]; then
    echo "Error: Profile config file not found: $ProfileINI"
    exit 1
fi

if [[ ! -d "$ProfileDirectory" ]]; then
    echo "Error: Profile directory not found: $ProfileDirectory"
    exit 1
fi

locations=(
    "$ProfileDirectory//"
    "//"
)

# Generate checksum for integrity verification
generate_checksum() {
    local file="$1"
    sha256sum "$file" | cut -d' ' -f1 > "${file}.sha256"
}

# Verify checksum at destination
verify_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"
    
    if [[ -f "$checksum_file" ]] && sha256sum -c "$checksum_file" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Add logging to a file
LOG_FILE="$HOME/firefox_backup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Usage:
log_message "Starting backup of $profile"

# Desktop notifications (Linux/Mac)
send_notification() {
    local message="$1"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Firefox Backup" "$message"
    elif command -v osascript >/dev/null 2>&1; then
        osascript -e "display notification \"$message\" with title \"Firefox Backup\""
    fi
    echo "$message"
}

# Function for Backing up files
backup_directory() {
    local profile="$1"
    local temp_archive="/tmp/${profile}${backup_date}.tar.bz2"
    
    log_message "Starting backup for: $profile"
    
    # Create archive
    if ! (cd "$ProfileDirectory" && tar jcf "$temp_archive" "$profile" --checkpoint=1000 --checkpoint-action=echo="#%u: %T"); then
        log_message "ERROR: Compression failed for $profile"
        rm -f "$temp_archive" 2>/dev/null
        send_notification "Backup failed for $profile"
        return 1
    fi
    
    # Generate checksum
    generate_checksum "$temp_archive"
    
    # Copy to all locations
    local success=true
    for location in "${locations[@]}"; do
        mkdir -p "$location" || continue
        
        if cp -v "$temp_archive" "$location/" && \
           cp -v "${temp_archive}.sha256" "$location/"; then
            log_message "✓ Copied to $location"
        else
            log_message "✗ Failed to copy to $location"
            success=false
        fi
        
        # Clean up old backups at this location
        cleanup_old_backups "$location"
    done
    
    # Cleanup temp files
    rm -f "$temp_archive" "${temp_archive}.sha256"
    
    if [[ "$success" == true ]]; then
        log_message "✓ Backup completed for $profile"
        send_notification "Backup completed for $profile"
        return 0
    else
        log_message "! Backup completed with errors for $profile"
        send_notification "Backup completed with errors for $profile"
        return 2
    fi
}
# Clean up old backups (keep only last 30 days)
cleanup_old_backups() {
    local location="$1"
    find "$location" -name "*.tar.bz2" -mtime +30 -delete
    find "$location" -name "*.sha256" -mtime +30 -delete
}

# Help function
show_help() {
    echo "Usage: $0 [OPTION]... [SELECTION]"
    echo "Firefox Profile Processor - Manage and execute operations on Firefox profiles"
    echo ""
    echo "If no SELECTION is provided, launches interactive mode."
    echo "If SELECTION is provided, executes non-interactively and exits."
    echo ""
    echo "SELECTION formats:"
    echo "  N           Single profile number (e.g., 1)"
    echo "  N,M,P       Multiple profiles (e.g., 1,3,5)"
    echo "  N-M         Range of profiles (e.g., 1-3)"
    echo "  all         All available profiles"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message and exit"
    echo "  -v, --verbose  Enable verbose output"
    echo "  -l, --list     List available profiles and exit"
    echo ""
    echo "Examples:"
    echo "  $0                       # Interactive mode with menu"
    echo "  $0 1,3,5                 # Process profiles 1, 3, and 5"
    echo "  $0 \"2-4\"                 # Process profiles 2 through 4"
    echo "  $0 all                   # Process all profiles"
    echo "  $0 --list                # Show available profiles and exit"
    echo "  $0 --verbose 1,2         # Process profiles 1 and 2 with verbose output"
    echo "  $0 -v \"1-3\"              # Process range 1-3 with verbose output"
    echo ""
    echo "Interactive mode controls:"
    echo "  0             Exit program"
    echo "  N             Single profile number"
    echo "  N,M,P         Multiple profiles separated by commas"
    echo "  N-M           Range of profiles"
    echo "  all           All available profiles"
    exit 0
}
# Function to display menu
display_menu() {
    echo "Detected OS: $OS_TYPE"
    echo ""
    echo "Available options:"
    for i in "${!ProfileNames[@]}"; do
        echo "$((i+1)). ${ProfileNames[i]}"
    done
    echo "$((${#ProfileNames[@]}+1)). All of them"
    echo "0. Exit"
    echo ""
    echo "Selection formats: 1, 1,3,5, 1-3, or 'all'"
    echo ""
}
# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -l|--list)
            SHOW_LIST=true
            shift
            ;;
        -*)
            echo "Error: Unknown option $1"
            echo "Try '$0 --help' for more information."
            exit 1
            ;;
        *)
            # First non-option argument is the selection
            SELECTION="$1"
            shift
            ;;
    esac
done

# Extract names and store them in an array
ProfileNames=()
while IFS= read -r line; do
    ProfileNames+=("$line")
done < <(awk -F= '/Name=/ {print $2}' "$ProfileINI")

# Show list and exit if --list flag is set
if [ "$SHOW_LIST" = true ]; then
    echo "Available Firefox Profiles:"
    for i in "${!ProfileNames[@]}"; do
        echo "$((i+1)). ${ProfileNames[i]}"
    done
    echo "Total: ${#ProfileNames[@]} profiles found"
    exit 0
fi

# Function to process selections
process_selection() {
    local selection="$1"
    
    if [ "$VERBOSE" = true ]; then
        echo "Debug: Processing selection '$selection'"
    fi
    
    if [[ "$selection" == "all" || "$selection" == $((${#ProfileNames[@]}+1)) ]]; then
        echo "Executing on ALL items:"
        for name in "${ProfileNames[@]}"; do
            Profile="$name"
            echo "Processing: $Profile"
            # Add your execution command here using $Profile
            backup_directory "$Profile"
        done
    else
        # Process comma-separated selections
        IFS=',' read -ra selections <<< "$selection"
        for sel in "${selections[@]}"; do
            sel=$(echo "$sel" | tr -d ' ')  # Remove spaces
            if [[ "$sel" == *-* ]]; then
                # Handle range (e.g., 1-3)
                start=${sel%-*}
                end=${sel#*-}
                if ! [[ "$start" =~ ^[0-9]+$ ]] || ! [[ "$end" =~ ^[0-9]+$ ]]; then
                    echo "Invalid range: $sel"
                    continue
                fi
                for ((i=start; i<=end; i++)); do
                    if [ $i -ge 1 ] && [ $i -le ${#ProfileNames[@]} ]; then
                        Profile="${ProfileNames[$((i-1))]}"
                        echo "Processing: $Profile"
                        # Add your execution command here using $Profile
                        backup_directory "$Profile"
                    else
                        echo "Invalid selection in range: $i"
                    fi
                done
            else
                # Handle single number
                if ! [[ "$sel" =~ ^[0-9]+$ ]]; then
                    echo "Invalid input: $sel"
                elif [ $sel -ge 1 ] && [ $sel -le ${#ProfileNames[@]} ]; then
                    Profile="${ProfileNames[$((sel-1))]}"
                    echo "Processing: $Profile"
                    # Add your execution command here using $Profile
                    backup_directory "$Profile"
                else
                    echo "Invalid selection: $sel"
                fi
            fi
        done
    fi
}

# Main script logic
if [ -n "$SELECTION" ]; then
    # If selection provided as argument, execute directly
    if [ "$VERBOSE" = true ]; then
        echo "Running in non-interactive mode"
        echo "Profile file: $ProfileINI"
        echo "Found ${#ProfileNames[@]} profiles"
    fi
    
    process_selection "$SELECTION"
    exit 0
else
    # If no arguments, show interactive menu
    if [ "$VERBOSE" = true ]; then
        echo "Running in interactive mode"
        echo "Profile file: $ProfileINI"
        echo "Found ${#ProfileNames[@]} profiles"
        echo ""
    fi
    
    while true; do
        display_menu
        
        # Get user input
        read -p "Enter your selection: " selection
        
        # Check for exit
        if [[ "$selection" == "0" ]]; then
            echo "Goodbye!"
            exit 0
        fi
        
        # Check for help in interactive mode
        if [[ "$selection" == "help" || "$selection" == "?" ]]; then
            echo ""
            echo "Interactive mode help:"
            echo "  0             - Exit program"
            echo "  N             - Single profile number (e.g., 1)"
            echo "  N,M,P         - Multiple profiles (e.g., 1,3,5)"
            echo "  N-M           - Range of profiles (e.g., 1-3)"
            echo "  all           - All available profiles"
            echo "  help or ?     - Show this help message"
            echo ""
            continue
        fi
        
        # Process selection
        process_selection "$selection"
        
        echo ""
        read -p "Press Enter to continue or Ctrl+C to exit..."
        echo "----------------------------------------"
    done
fi