# Initialize variables
CLI_PATH=""
PATCHES_PATH=""
APP_PATH=""
INCLUDE_PATCHES=()
EXCLUDE_PATCHES=()
KEYSTORE_NAME=""
OUTPUT_FILENAME=""
PACKAGE_NAME=""
EXCLUSIVE_MODE="false"
ADB_INSTALL="false"

# Parse command line arguments
SKIP_UPDATE=false
for arg in "$@"; do
    case "$arg" in
        --noupdate)
            SKIP_UPDATE=true
            ;;
    esac
done

# Auto update function
auto_update_and_select() {
    echo "Performing auto-update and selection..."
    update_file_from_github "CLI" "auto"
    update_file_from_github "PATCHES" "auto"
}

# Download and update ReVanced files from GitHub
update_file_from_github() {
    local type="$1"
    local mode="${2:-manual}"  # Default mode is manual if not provided
    local repo=""
    local file_extension=""

    # Check if jq is installed
    [ $(command -v jq) ] || { echo "jq not found, please install for JSON parsing." >&2; return 1; }

    # Define repository and file extension based on type
    case "$type" in
        "CLI")
            repo="ReVanced/revanced-cli"
            file_extension="jar"
            ;;
        "PATCHES")
            repo="ReVanced/revanced-patches"
            file_extension="rvp"
            ;;
        *)
            echo "Invalid type."
            return 1
            ;;
    esac

    # If in auto mode, directly update from GitHub
    if [ "$mode" = "auto" ]; then
        choice="Update from GitHub"
    else
        # In manual mode, ask the user what they want to do
        echo "Do you want to update the $type file from GitHub or choose a local file?"
        select choice in "Update from GitHub" "Choose local file"; do
            case "$choice" in
                "Update from GitHub"|"Choose local file")
                    break
                    ;;
                *)
                    echo "Invalid choice. Please select a valid option."
                    ;;
            esac
        done
    fi

    # Now check the user's choice and act accordingly
    if [ "$choice" = "Update from GitHub" ]; then
        # Check for internet connection only if the user chooses to update from GitHub
        if ping -n 1 github.com &> /dev/null; then
            # Internet connection available, proceed with GitHub update
            release_url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | jq -r ".assets[] | select(.name | endswith(\".$file_extension\")) | .browser_download_url")

            if [ -z "$release_url" ]; then
                echo "Error: Download URL not found."
                return 1
            fi

            filename=$(basename "$release_url")
            local_path="./revanced/$filename"

            if [[ -f "$local_path" ]]; then
                echo "$filename is already up to date. Setting its path..."
            else
                echo "Downloading $filename..."
                mkdir -p ./revanced
                curl -L "$release_url" -o "$local_path" && echo "Downloaded and saved to $local_path."
            fi

            # Dynamically setting the path variable based on type
            eval "${type}_PATH=\$local_path"
        else
            echo "No internet connection. Selecting latest local version for $type."
            select_latest_local_version "$type"
        fi
    elif [ "$choice" = "Choose local file" ]; then
        # If the user wants to choose a local file, use the helper function to do so
        choose_file_path "$type"
    fi
}

select_latest_local_version() {
    local type="$1"
    local extension
    local prefix
    local search_dir="./revanced"

    case "$type" in
        "CLI")
            extension="jar"
            prefix="revanced-cli"
            ;;
        "PATCHES")
            extension="rvp"
            prefix="patches"
            ;;
        "APP") # This should never run, but just in case
            echo "Invalid type."
            return 1
            ;;
    esac

    latest_file=$(find "$search_dir" -name "${prefix}*.$extension" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")

    if [ -n "$latest_file" ]; then
        eval "${type}_PATH='$latest_file'"
        echo "Selected latest $type file: $latest_file"
    else
        echo "No local $type file found."
    fi
}

# Extract the package name from an APK file
get_package_name() {
    local apk="$1"
    [[ -f "$apk" ]] || { echo ""; return; }

    if command -v aapt &>/dev/null; then
        aapt dump badging "$apk" 2>/dev/null | grep "^package:" | sed "s/^package: name='\([^']*\)'.*/\1/"
        return
    fi

    if command -v aapt2 &>/dev/null; then
        aapt2 dump badging "$apk" 2>/dev/null | grep "^package:" | sed "s/^package: name='\([^']*\)'.*/\1/"
        return
    fi

    if command -v python3 &>/dev/null; then
        python3 - "$apk" <<'PYEOF'
import sys, zipfile, struct, re

def read_strings(data, off):
    string_count  = struct.unpack_from('<I', data, off + 8)[0]
    flags         = struct.unpack_from('<I', data, off + 16)[0]
    strings_start = struct.unpack_from('<I', data, off + 20)[0]
    offs_base     = off + 28
    str_base      = off + strings_start
    utf8          = bool(flags & 0x100)
    strings = []
    for i in range(string_count):
        str_off = struct.unpack_from('<I', data, offs_base + i * 4)[0]
        p = str_base + str_off
        try:
            if utf8:
                u8len = data[p + 1]
                s = data[p + 2 : p + 2 + u8len].decode('utf-8', errors='ignore')
            else:
                char_count = struct.unpack_from('<H', data, p)[0]
                s = data[p + 2 : p + 2 + char_count * 2].decode('utf-16-le', errors='ignore')
            strings.append(s)
        except Exception:
            strings.append('')
    return strings

try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        data = z.read('AndroidManifest.xml')
    pkg_re = re.compile(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$')
    for s in read_strings(data, 8):
        if pkg_re.match(s):
            print(s)
            sys.exit(0)
except Exception:
    pass
PYEOF
        return
    fi

    echo ""
}

# Function to choose arbitrary file path
choose_file_path() {
    local type="$1"
    local extension description

    case "$type" in
        "CLI")
            extension="jar"
            description="ReVanced CLI"
            ;;
        "PATCHES")
            extension="rvp"
            description="ReVanced Patches"
            ;;
        "APP")
            extension="apk"
            description="APK files"
            ;;
        *)
            echo "Invalid type."
            return
            ;;
    esac

    # Call PowerShell script to open Windows file explorer dialog
    local file_path=$(powershell.exe -ExecutionPolicy Bypass -File "$(dirname "$0")/file_picker.ps1" "$description|*.$extension")
    
    if [[ -n "$file_path" ]]; then
        local var_name="${type}_PATH"  # Constructs the variable name
        eval "${var_name}='$file_path'"  # Assigns the path to the dynamically named variable

        echo "Selected $type file path: ${!var_name}"

        if [[ "$type" == "APP" ]]; then
            PACKAGE_NAME=$(get_package_name "$file_path")
            if [[ -n "$PACKAGE_NAME" ]]; then
                echo "Detected package name: $PACKAGE_NAME"
            else
                echo "Could not detect package name automatically."
            fi
        fi
    else
        echo "No $type file selected."
    fi
}

# Function to include or exclude patches from a list
choose_patches_from_list() {
    local mode=$1
    local selected_patches=()

    if [ "$mode" != "incl" ] && [ "$mode" != "excl" ]; then
        echo "Invalid mode: $mode"
        return 1
    fi

    # Ask for package name then search for patches (default to detected package name)
    local default_query="${PACKAGE_NAME}"
    read -p "Search by package name [${default_query}]: " search_query
    search_query="${search_query:-$default_query}"

    echo "Available patches:"
    java -jar "$CLI_PATH" list-patches -p "$PATCHES_PATH" -b --filter-package-name="$search_query"
    echo ""

    # Enter index selection loop
    while true; do
        read -p "Enter patch index (or nothing to finish) [${selected_patches[*]}]: " input
        if [[ -z $input ]]; then
            break
        elif [[ $input =~ ^[0-9]+$ ]]; then
            selected_patches+=("$input")
        fi
        echo "" # Add empty line as separator
    done

    # Check if no patches were selected
    if [[ ${#selected_patches[@]} -eq 0 ]]; then
        echo "No patches added. Selection unmodified."
        return
    fi

    # Add selected patches to the respective array
    if [ "$mode" == "incl" ]; then
        INCLUDE_PATCHES+=(${selected_patches[@]})
    elif [ "$mode" == "excl" ]; then 
        EXCLUDE_PATCHES+=(${selected_patches[@]})
    fi

    echo "Selected patches: ${selected_patches[*]}"
}

# RV Patching function
apply_rvpatches() {
    if [[ -n "$CLI_PATH" && -n "$APP_PATH" && -n "$PATCHES_PATH" ]]; then
        if [[ -f "$CLI_PATH" && -f "$APP_PATH" && -f "$PATCHES_PATH" ]]; then
            if [[ "$EXCLUSIVE_MODE" = "false" || -n "$INCLUDE_PATCHES" ]]; then
                read -p "Enter output file name (without extension): " OUTPUT_FILENAME
                if [[ -n "$OUTPUT_FILENAME" ]]; then
                    mkdir -p ./output
                    mkdir -p ./revanced-resource-cache
                    cache_path="$PWD/revanced-resource-cache"
                    IFS=' ' # Reset IFS
                    include_args=()
                    exclude_args=()
                    
                    for i in "${INCLUDE_PATCHES[@]}"; do
                        include_args+=("--ei=$i")
                    done

                    for i in "${EXCLUDE_PATCHES[@]}"; do
                        exclude_args+=("--di=$i")
                    done

                    # Create an array for all arguments
                    args=(
                        -jar "$CLI_PATH"
                        patch
                        "$APP_PATH"
                        -p "$PATCHES_PATH"
                        -b
                        -t "$cache_path"
                        --purge
                        -o "./output/$OUTPUT_FILENAME.apk"
                    )

                    # Add keystore argument if set
                    if [[ -n "$KEYSTORE_NAME" ]]; then
                        args+=("--keystore" "./output/$KEYSTORE_NAME.keystore")
                    fi

                    # Add adb install argument if set
                    if [[ "$ADB_INSTALL" == "true" ]]; then
                        args+=("--install")
                    fi

                    # Add include and exclude arguments
                    args+=("${include_args[@]}" "${exclude_args[@]}")

                    # Debugging: Print the constructed arguments
                    echo "Executing command with arguments: ${args[*]}"

                    # Execute the command with the constructed arguments
                    java "${args[@]}"
                    
                    # Error checking and finish up
                    exit_code=$?

                    if [ $exit_code -ne 0 ]; then
                        echo "ERROR: Failed to apply patches!"
                        echo "Exit code: $exit_code"
                    fi
                fi
            else
                echo "ERROR: Exclusive mode is on, but no patches are included."
            fi
        else
            echo "ERROR: One of the required files do not exist or are currently unavailable."
        fi
    else
        echo "ERROR: Missing required paths. Please set all required file paths."
    fi
}

# List supported app versions for a package name from the patches
list_supported_versions() {
    if [[ -z "$CLI_PATH" || -z "$PATCHES_PATH" ]]; then
        echo "Please select CLI and Patches files first."
        return
    fi
    local default_query="${PACKAGE_NAME}"
    read -p "Enter package name to look up [${default_query}]: " pkg
    pkg="${pkg:-$default_query}"
    if [[ -z "$pkg" ]]; then
        echo "No package name provided."
        return
    fi
    echo ""
    echo "Supported versions for: $pkg"
    java -jar "$CLI_PATH" list-versions -p "$PATCHES_PATH" -b -f "$pkg"
}

# Function for confirming exit
confirm_exit() {
    read -p "Are you sure you want to exit? (Y/N): " choice
    case "${choice:0:1}" in
        [Yy])
            echo "Exiting..."
            exit 0
            ;;
        [Nn])
            ;;
        *)
            echo "Invalid choice. Please enter Y or N."
            confirm_exit
            ;;
    esac
}

# Function to display the menu
display_menu() {
    clear
    IFS=', ' # Set IFS to comma for patch list readability

    # Header
    echo "=================="
    echo "   RV-CLI Menu"
    echo "=================="

    # Menu Options
    echo -e "\e[1;32mA. Update/select CLI\e[0m"
    echo -e "\e[1;36mB. Update/select Patches\e[0m"
    echo -e "\e[1;33mC. Set keystore name (optional)\e[0m"
    echo -e "\e[1;33mD. Toggle ADB install (Current: \e[1;31m$ADB_INSTALL\e[1;33m)\e[0m"
    echo -e "\e[1;33mE. Toggle Exclusive Mode (Current: \e[1;31m$EXCLUSIVE_MODE\e[1;33m)\e[0m"
    echo
    echo -e "\e[1;33m1. Choose APK path\e[0m"
    echo -e "\e[1;33m2. Include patches from list\e[0m"
    echo -e "\e[1;33m3. Exclude patches from list\e[0m"
    echo -e "\e[1;32m4. Apply patches!\e[0m"
    echo -e "\e[1;36m5. List supported app versions\e[0m"
    echo -e "\e[1;31m6. Exit\e[0m"
    echo -e "\e[1;33m----------\e[0m"

    # Selected Paths
    echo -e "\e[1;32mCLI JAR: \e[1;31m$CLI_PATH\e[0m"
    echo -e "\e[1;36mPatches RVP: \e[1;31m$PATCHES_PATH\e[0m"
    echo -e "\e[1;33mKeystore name: \e[1;31m$KEYSTORE_NAME\e[0m"
    echo -e "\e[1;33mApp APK: \e[1;31m$APP_PATH\e[0m"
    echo -e "\e[1;33mPackage name: \e[1;31m$PACKAGE_NAME\e[0m"
    echo

    # Included and Excluded Patches
    echo -e "\e[1;33mIncluded patches: ${INCLUDE_PATCHES[@]}\e[0m"
    echo -e "\e[1;33mExcluded patches: ${EXCLUDE_PATCHES[@]}\e[0m"
    echo
}

# Only run auto-update if not skipped
if [ "$SKIP_UPDATE" = false ]; then
    auto_update_and_select
fi

# Main loop
while true; do
    display_menu
    IFS=' ' # Reset IFS to avoid any errors

    read -p "Choose an option: " choice
    case "$choice" in
        [Aa]) # Update CLI option
            update_file_from_github "CLI" "manual"
            ;;
        [Bb]) # Update patches option
            update_file_from_github "PATCHES" "manual"
            ;;
        [Cc]) # Keystore name option
            read -p "Enter keystore name: " KEYSTORE_NAME
            echo "Keystore name set to: $KEYSTORE_NAME"
            ;;
        [Dd]) # Toggle ADB install option
            ADB_INSTALL="$( [[ "$ADB_INSTALL" == "true" ]] && echo "false" || echo "true" )"
            echo "ADB install $( [[ "$ADB_INSTALL" == "true" ]] && echo "enabled" || echo "disabled" )."
            ;;
        [Ee]) # Toggle Exclusive Mode option
            EXCLUSIVE_MODE="$( [[ "$EXCLUSIVE_MODE" == "true" ]] && echo "false" || echo "true" )"
            echo "Exclusive mode $( [[ "$EXCLUSIVE_MODE" == "true" ]] && echo "enabled" || echo "disabled" )."
            ;;
        1) # Choose app APK path option
            choose_file_path "APP"
            ;;
        2) # Include patches from list option
            if [[ -n "$CLI_PATH" && -n "$APP_PATH" && -n "$PATCHES_PATH" ]]; then
                # Check if INCLUDE_PATCHES is already set, and if not, ask to reset it
                if [[ -n "$INCLUDE_PATCHES" ]]; then
                    read -p "Included patches list is already set. Reset them? (yN):" choice
                    case "${choice:0:1}" in 
                        [Yy])
                            # Reset INCLUDE_PATCHES array
                            INCLUDE_PATCHES=()
                            echo "Included patches have been reset."
                            ;;
                        *)
                            ;;
                    esac
                fi
                echo ""
                choose_patches_from_list "incl"
            else
                echo "Please choose CLI, app APK, and patches paths first."
            fi
            ;;
        3) # Exclude patches from list option
            if [[ -n "$CLI_PATH" && -n "$APP_PATH" && -n "$PATCHES_PATH" ]]; then
                # Check if EXCLUDE_PATCHES is already set, and if not, ask to reset it
                if [[ -n "$EXCLUDE_PATCHES" ]]; then
                    read -p "Excluded patches list is already set. Reset them? (yN):" choice
                    case "${choice:0:1}" in 
                        [Yy])
                            # Reset EXCLUDE_PATCHES array
                            EXCLUDE_PATCHES=()
                            echo "Excluded patches have been reset."
                            ;;
                        *)
                            ;;
                    esac
                fi
                echo ""
                choose_patches_from_list "excl"
            else
                echo "Please choose CLI, app APK, and patches paths first."
            fi
            ;;
        4) # Patch app option
            apply_rvpatches
            ;;
        5) # List supported versions option
            list_supported_versions
            ;;
        6) # Exit option
            confirm_exit
            ;;
        *) # Invalid option failsafe
            echo "Invalid choice. Please select a valid option."
            ;;
    esac
    echo ""
    read -p "Press Enter to return to menu..."
done
