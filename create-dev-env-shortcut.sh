#!/bin/bash

# --- START: Get Terminal Choice ---
TERMINAL_CHOICE=$1

if [[ -z "$TERMINAL_CHOICE" ]]; then
    read -p "Choose terminal: (1) ptyxis (2) wezterm: " term_choice
    if [[ "$term_choice" == "2" ]]; then
        TERMINAL_CHOICE="wezterm"
    else
        TERMINAL_CHOICE="ptyxis" # Default
    fi
fi
echo "Configuring shortcuts for: $TERMINAL_CHOICE"
# --- END: Get Terminal Choice ---


# --- START: User Prompts ---
read -p "Enter the Podman container name (e.g., 'dev'): " CONTAINER_NAME
if [[ -z "$CONTAINER_NAME" ]]; then
    echo "No container name entered. Aborting."
    exit 1
fi

# Shortcut 1: Terminal
SHORTCUT_NAME_TERM="Launch $CONTAINER_NAME Terminal"
read -p "Enter key binding for Terminal (e.g., '<Super>t'): " KEY_BINDING_TERM
if [[ -z "$KEY_BINDING_TERM" ]]; then echo "Aborting."; exit 1; fi

# Shortcut 2: Neovide
SHORTCUT_NAME_GUI="Launch $CONTAINER_NAME Neovide"
read -p "Enter key binding for Neovide (e.g., '<Super>n'): " KEY_BINDING_GUI
if [[ -z "$KEY_BINDING_GUI" ]]; then echo "Aborting."; exit 1; fi

# Get current user for working dir
CURRENT_USER=$(whoami)

# --- Define Commands ---

# 1. Terminal Command Construction
if [[ "$TERMINAL_CHOICE" == "wezterm" ]]; then
    # Wezterm: Launch zsh directly
    PODMAN_CMD="podman exec -it -w '/home/$CURRENT_USER' --env WAYLAND_DISPLAY=$WAYLAND_DISPLAY $CONTAINER_NAME /bin/zsh"
    CMD_TERM="flatpak run org.wezfurlong.wezterm start -- $PODMAN_CMD"
else
    # Ptyxis: Launch zsh -> tmux
    # Note: Added 'podman start' before exec to ensure it works if stopped
    PODMAN_CMD="podman start $CONTAINER_NAME && podman exec -it -w '/home/$CURRENT_USER' --env WAYLAND_DISPLAY=$WAYLAND_DISPLAY $CONTAINER_NAME /bin/zsh -c 'tmux -u'"
    CMD_TERM="ptyxis --fullscreen --command \"/bin/sh -c '$PODMAN_CMD'\""
fi

# 2. Neovide Command Construction
# Logic: Start container -> Start Nvim Server (if not running) -> Launch Neovide
CMD_GUI="sh -c \"podman start $CONTAINER_NAME && podman exec -d $CONTAINER_NAME nvim --headless --listen 0.0.0.0:6000; neovide --server=localhost:6000\""

# --- END: User Prompts ---


# --- GNOME Settings Logic ---
BASE_GSETTINGS_PATH="org.gnome.settings-daemon.plugins.media-keys"
KEYBINDING_LIST_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Helper function to add a single shortcut
add_shortcut() {
    local name="$1"
    local command="$2"
    local binding="$3"

    # Get current list freshly every time (since we modify it in the loop)
    local current_list=$(gsettings get $BASE_GSETTINGS_PATH custom-keybindings)

    # Check if exists
    local existing_paths=$(echo "$current_list" | grep -o "'[^']*'" | tr -d "'")
    for path in $existing_paths; do
        local existing_name=$(gsettings get "$BASE_GSETTINGS_PATH.custom-keybinding:$path" name | tr -d "'")
        if [[ "$existing_name" == "$name" ]]; then
            echo "Warning: Shortcut '$name' already exists. Skipping."
            return
        fi
    done

    # Find next index
    local last_index=$(echo "$current_list" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -1)
    
    local new_index=0
    local new_list=""
    
    if [[ -z "$last_index" ]]; then
        new_index=0
        new_list="['$KEYBINDING_LIST_PATH/custom$new_index/']"
    else
        new_index=$((last_index + 1))
        # Append to the list string safely
        if [[ "$current_list" == "@as []" ]]; then
             new_list="['$KEYBINDING_LIST_PATH/custom$new_index/']"
        else
             new_list=${current_list/]/", '$KEYBINDING_LIST_PATH/custom$new_index/']"}
        fi
    fi

    local new_path="$KEYBINDING_LIST_PATH/custom$new_index/"

    # Apply settings
    gsettings set $BASE_GSETTINGS_PATH custom-keybindings "$new_list"
    gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_path" name "$name"
    gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_path" command "$command"
    gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_path" binding "$binding"

    echo "Created: '$name' ($binding)"
}

# --- Execute Creation ---
echo "-----------------------------------"
add_shortcut "$SHORTCUT_NAME_TERM" "$CMD_TERM" "$KEY_BINDING_TERM"
add_shortcut "$SHORTCUT_NAME_GUI" "$CMD_GUI" "$KEY_BINDING_GUI"
echo "-----------------------------------"
echo "All shortcuts configured!"
