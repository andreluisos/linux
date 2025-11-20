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
read -p "Enter key binding for Neovide (e.g., '<Super>r'): " KEY_BINDING_GUI
if [[ -z "$KEY_BINDING_GUI" ]]; then echo "Aborting."; exit 1; fi

# Get current user for working dir
CURRENT_USER=$(whoami)

# --- START: Path Detection (The Fix for GNOME) ---
# GNOME Shortcuts don't load your .zshrc/.bashrc, so they don't know your PATH.
# We find the absolute paths now and bake them into the command.

PODMAN_BIN=$(command -v podman)
if [[ -z "$PODMAN_BIN" ]]; then PODMAN_BIN="/usr/bin/podman"; fi

NEOVIDE_BIN=$(command -v neovide)
if [[ -z "$NEOVIDE_BIN" ]]; then 
    echo "WARNING: 'neovide' not found in PATH. Assuming 'neovide'..."
    NEOVIDE_BIN="neovide"
fi
# -------------------------------------------------

# --- Define Commands ---

# 1. Terminal Command Construction
if [[ "$TERMINAL_CHOICE" == "wezterm" ]]; then
    # Wezterm
    PODMAN_CMD="$PODMAN_BIN exec -it -w '/home/$CURRENT_USER' --env WAYLAND_DISPLAY=$WAYLAND_DISPLAY $CONTAINER_NAME /bin/zsh"
    CMD_TERM="flatpak run org.wezfurlong.wezterm start -- $PODMAN_CMD"
else
    # Ptyxis (Using your fix: -x)
    PODMAN_CMD="$PODMAN_BIN exec -it -w '/home/$CURRENT_USER' $CONTAINER_NAME /bin/zsh -c 'tmux -u'"
    CMD_TERM="ptyxis -x \"$PODMAN_CMD\" --fullscreen"
fi

# 2. Neovide Command Construction
# - Uses absolute paths ($PODMAN_BIN, $NEOVIDE_BIN)
# - Explicitly calls /bin/sh to handle the && and ; logic
CMD_GUI="sh -c \"$PODMAN_BIN start $CONTAINER_NAME && $PODMAN_BIN exec -d -w /home/$CURRENT_USER --env SHELL=/usr/bin/zsh $CONTAINER_NAME nvim --headless --listen 0.0.0.0:6000; $NEOVIDE_BIN --server=localhost:6000\""

# --- END: User Prompts ---


# --- GNOME Settings Logic ---
BASE_GSETTINGS_PATH="org.gnome.settings-daemon.plugins.media-keys"
KEYBINDING_LIST_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Helper function to add a single shortcut
add_shortcut() {
    local name="$1"
    local command="$2"
    local binding="$3"

    # Get current list freshly every time
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
echo "Neovide path detected as: $NEOVIDE_BIN"
echo "Podman path detected as:  $PODMAN_BIN"
echo "-----------------------------------"
add_shortcut "$SHORTCUT_NAME_TERM" "$CMD_TERM" "$KEY_BINDING_TERM"
add_shortcut "$SHORTCUT_NAME_GUI" "$CMD_GUI" "$KEY_BINDING_GUI"
echo "-----------------------------------"
echo "All shortcuts configured! Please test your hotkeys."
