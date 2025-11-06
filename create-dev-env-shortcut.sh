#!/bin/bash

# --- START: User Prompts ---
read -p "Enter a name for this shortcut (e.g., 'Launch Dev Project'): " SHORTCUT_NAME
if [[ -z "$SHORTCUT_NAME" ]]; then
    echo "No shortcut name entered. Aborting."
    exit 1
fi

read -p "Enter the exact name of the podman container to launch: " CONTAINER_NAME
if [[ -z "$CONTAINER_NAME" ]]; then
    echo "No container name entered. Aborting."
    exit 1
fi

read -p "Enter the key binding (e.g., '<Super>t'): " KEY_BINDING
if [[ -z "$KEY_BINDING" ]]; then
    echo "No key binding entered. Aborting."
    exit 1
fi

# Get the current user's name to set the working directory inside the container
CURRENT_USER=$(whoami)

# Dynamically create the command
COMMAND_TO_RUN="ptyxis -x \"podman exec -it -w '/home/$CURRENT_USER' --env WAYLAND_DISPLAY=$WAYLAND_DISPLAY $CONTAINER_NAME /bin/zsh -c 'tmux -u'\" --fullscreen"
# --- END: User Prompts ---


# Base path for all custom keybindings
BASE_GSETTINGS_PATH="org.gnome.settings-daemon.plugins.media-keys"
KEYBINDING_LIST_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Get the current list of custom keybindings
current_list=$(gsettings get $BASE_GSETTINGS_PATH custom-keybindings)

# --- START: Check for existing shortcut by name ---
existing_paths=$(echo "$current_list" | grep -o "'[^']*'" | tr -d "'")

for path in $existing_paths; do
    existing_name=$(gsettings get "$BASE_GSETTINGS_PATH.custom-keybinding:$path" name | tr -d "'")

    if [[ "$existing_name" == "$SHORTCUT_NAME" ]]; then
        echo "Shortcut '$SHORTCUT_NAME' already exists. Aborting script."
        echo "If you want to update it, please remove the old one from GNOME Settings first."
        exit 0
    fi
done
# --- END: Check for existing shortcut by name ---

# Find the highest existing index number
last_index=$(echo "$current_list" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -1)

# Determine the new index and construct the new list
if [[ -z "$last_index" ]]; then
  new_index=0
  new_list="['$KEYBINDING_LIST_PATH/custom$new_index/']"
  echo "No existing shortcuts found. Creating new list."
else
  new_index=$((last_index + 1))
  new_list=${current_list/]/", '$KEYBINDING_LIST_PATH/custom$new_index/']"}
  echo "Found existing shortcuts. Appending new one."
fi

# The full path for the new keybinding's settings
new_shortcut_path="$KEYBINDING_LIST_PATH/custom$new_index/"

# --- Apply all the new settings ---
echo "Setting keybinding list..."
gsettings set $BASE_GSETTINGS_PATH custom-keybindings "$new_list"

echo "Configuring shortcut 'custom$new_index'..."
gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_shortcut_path" name "$SHORTCUT_NAME"
gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_shortcut_path" command "$COMMAND_TO_RUN"
gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_shortcut_path" binding "$KEY_BINDING"
echo "Success! Shortcut '$SHORTCUT_NAME' should now be active with binding '$KEY_BINDING'."
