#!/bin/bash

SHORTCUT_NAME="Launch Ghostty"
COMMAND_TO_RUN="$HOME/.local/bin/ghostty"
KEY_BINDING="<Super>t"
# -----------------------------------------


# Base path for all custom keybindings
BASE_GSETTINGS_PATH="org.gnome.settings-daemon.plugins.media-keys"
KEYBINDING_LIST_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Get the current list of custom keybindings
current_list=$(gsettings get $BASE_GSETTINGS_PATH custom-keybindings)

# --- START: Check for existing shortcut by name ---
# Extract individual paths from the GSettings list string (e.g., '/.../custom0/').
# The `grep -o` finds all single-quoted strings, and `tr -d "'"` removes the quotes.
existing_paths=$(echo "$current_list" | grep -o "'[^']*'" | tr -d "'")

for path in $existing_paths; do
    # Get the name of the current shortcut in the loop.
    # The output from gsettings includes single quotes, so we remove them with `tr`.
    existing_name=$(gsettings get "$BASE_GSETTINGS_PATH.custom-keybinding:$path" name | tr -d "'")

    # If a shortcut with the same name is found, print a message and exit.
    if [[ "$existing_name" == "$SHORTCUT_NAME" ]]; then
        echo "Shortcut '$SHORTCUT_NAME' already exists. Aborting script."
        exit 0 # Exit successfully as no action is needed.
    fi
done
# --- END: Check for existing shortcut by name ---

# Find the highest existing index number (e.g., the '1' in 'custom1')
# This is a reliable way to check if any custom keybindings exist.
last_index=$(echo "$current_list" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -1)

# Determine the new index and construct the new list of keybindings
if [[ -z "$last_index" ]]; then
  # If no custom shortcuts exist, start with index 0 and create a new list.
  new_index=0
  new_list="['$KEYBINDING_LIST_PATH/custom$new_index/']"
  echo "No existing shortcuts found. Creating new list."
else
  # If shortcuts exist, increment the last index and append to the list.
  new_index=$((last_index + 1))
  # This substitution is a safe way to append inside the list's brackets.
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
