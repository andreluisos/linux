#!/bin/bash
# Interactive container rebuild script
# Creates a distrobox container with optional isolated home directory

set -e

# Prompt for container name
read -p "Container name: " CONTAINER_NAME

# Validate container name
if [ -z "$CONTAINER_NAME" ]; then
    echo "❌ Container name cannot be empty"
    exit 1
fi

# Prompt for isolated home folder
echo ""
echo "Create isolated home folder?"
echo "  yes - Creates isolated home at: $HOME/Documents/containers/${CONTAINER_NAME}"
echo "  no  - Uses your regular home directory"
read -p "Isolated home? (yes/no) [yes]: " USE_ISOLATED_HOME
USE_ISOLATED_HOME=${USE_ISOLATED_HOME:-yes}

# Determine home directory path
if [[ "$USE_ISOLATED_HOME" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    CONTAINER_HOME="$HOME/Documents/containers/${CONTAINER_NAME}"
    HOME_FLAG="--home $CONTAINER_HOME"
    echo "📁 Using isolated home: $CONTAINER_HOME"
else
    CONTAINER_HOME="$HOME"
    HOME_FLAG=""
    echo "📁 Using regular home: $HOME"
fi

# Prompt for Neovim server port
echo ""
read -p "Neovim server port [6000]: " NVIM_PORT
NVIM_PORT=${NVIM_PORT:-6000}

# Validate port is a number
if ! [[ "$NVIM_PORT" =~ ^[0-9]+$ ]]; then
    echo "❌ Port must be a number"
    exit 1
fi

# Prompt for keyboard shortcut
echo ""
read -p "Enter key binding for Neovide (e.g., '<Super>t') [<Super>t]: " KEY_BINDING
KEY_BINDING=${KEY_BINDING:-<Super>t}

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo "Container name: $CONTAINER_NAME"
echo "Home directory: $CONTAINER_HOME"
echo "Image:          fedora:latest"
echo "Neovim port:    $NVIM_PORT"
echo "Keyboard shortcut: $KEY_BINDING"
echo "=========================================="
echo ""
read -p "Proceed with creation? (yes/no) [yes]: " CONFIRM
CONFIRM=${CONFIRM:-yes}

if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "❌ Cancelled"
    exit 0
fi

echo ""
echo "🔄 Removing existing '$CONTAINER_NAME' container (if exists)..."
distrobox rm "$CONTAINER_NAME" --force 2>/dev/null || true

echo "📦 Creating new '$CONTAINER_NAME' container..."
# We only include systemd here - all other packages will be installed by setup.sh
if [ -n "$HOME_FLAG" ]; then
    distrobox create --name "$CONTAINER_NAME" --yes \
      --image fedora:latest \
      --init \
      $HOME_FLAG \
      --additional-packages "systemd"
else
    distrobox create --name "$CONTAINER_NAME" --yes \
      --image fedora:latest \
      --init \
      --additional-packages "systemd"
fi

echo "🚀 Starting container (this will take a few minutes)..."
echo "   Distrobox is installing basic packages..."

# Start the container in the background by entering it
distrobox enter "$CONTAINER_NAME" -- echo "Container initialized successfully" > /dev/null 2>&1

# Wait for container to be actually running
echo "⏳ Waiting for container to be ready..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if podman exec "$CONTAINER_NAME" true 2>/dev/null; then
        echo "✅ Container is ready!"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "❌ Timeout waiting for container to start"
    exit 1
fi

echo "🔧 Downloading and running setup script from GitHub..."
podman exec -u root "$CONTAINER_NAME" bash -c "export NVIM_PORT=$NVIM_PORT && curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/dev-setup.sh | bash"

echo "⏳ Waiting for Neovim server to start..."
sleep 5

# Verify Neovim server is running
if podman exec "$CONTAINER_NAME" ss -tlnp | grep -q "$NVIM_PORT"; then
    echo "✅ Neovim server is running on 127.0.0.1:$NVIM_PORT"
else
    echo "⚠️  Neovim server may not be ready yet. You can check with:"
    echo "   podman exec $CONTAINER_NAME ss -tlnp | grep $NVIM_PORT"
fi

# Create Neovide shortcut
echo ""
echo "🔧 Creating Neovide keyboard shortcut..."

SHORTCUT_NAME="Launch $CONTAINER_NAME Neovide"
CMD_NEOVIDE="neovide --server 127.0.0.1:$NVIM_PORT"

BASE_GSETTINGS_PATH="org.gnome.settings-daemon.plugins.media-keys"
KEYBINDING_LIST_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Get current list
current_list=$(gsettings get $BASE_GSETTINGS_PATH custom-keybindings)

# Check if exists
existing_paths=$(echo "$current_list" | grep -o "'[^']*'" | tr -d "'")
shortcut_exists=false
for path in $existing_paths; do
    existing_name=$(gsettings get "$BASE_GSETTINGS_PATH.custom-keybinding:$path" name 2>/dev/null | tr -d "'")
    if [[ "$existing_name" == "$SHORTCUT_NAME" ]]; then
        echo "⚠️  Shortcut '$SHORTCUT_NAME' already exists. Skipping."
        shortcut_exists=true
        break
    fi
done

if [ "$shortcut_exists" = false ]; then
    # Find next index
    last_index=$(echo "$current_list" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -1)
    
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

    new_path="$KEYBINDING_LIST_PATH/custom$new_index/"

    # Apply settings
    gsettings set $BASE_GSETTINGS_PATH custom-keybindings "$new_list"
    gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_path" name "$SHORTCUT_NAME"
    gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_path" command "$CMD_NEOVIDE"
    gsettings set "$BASE_GSETTINGS_PATH.custom-keybinding:$new_path" binding "$KEY_BINDING"

    echo "✅ Created shortcut: '$SHORTCUT_NAME' ($KEY_BINDING)"
fi

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "Container:      $CONTAINER_NAME"
echo "Home directory: $CONTAINER_HOME"
echo "Neovim server:  127.0.0.1:$NVIM_PORT"
echo ""
echo "To connect with Neovide:"
echo "  - Use keyboard shortcut: $KEY_BINDING"
echo "  - Or run: neovide --server 127.0.0.1:$NVIM_PORT"
echo ""
echo "To enter the container, run:"
echo "  distrobox enter $CONTAINER_NAME"
echo ""
