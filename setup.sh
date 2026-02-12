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
echo "  yes - Creates isolated home at: $HOME/Documents/containers/${CONTAINER_NAME}-home"
echo "  no  - Uses your regular home directory"
read -p "Isolated home? (yes/no) [yes]: " USE_ISOLATED_HOME
USE_ISOLATED_HOME=${USE_ISOLATED_HOME:-yes}

# Determine home directory path
if [[ "$USE_ISOLATED_HOME" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    CONTAINER_HOME="$HOME/Documents/containers/${CONTAINER_NAME}-home"
    HOME_FLAG="--home $CONTAINER_HOME"
    echo "📁 Using isolated home: $CONTAINER_HOME"
else
    CONTAINER_HOME="$HOME"
    HOME_FLAG=""
    echo "📁 Using regular home: $HOME"
fi

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo "Container name: $CONTAINER_NAME"
echo "Home directory: $CONTAINER_HOME"
echo "Image:          fedora:latest"
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
podman exec -u root "$CONTAINER_NAME" bash -c "curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/dev-setup.sh | bash"

echo "⏳ Waiting for Neovim server to start..."
sleep 5

# Verify Neovim server is running
if podman exec "$CONTAINER_NAME" ss -tlnp | grep -q 6666; then
    echo "✅ Neovim server is running on 127.0.0.1:6666"
else
    echo "⚠️  Neovim server may not be ready yet. You can check with:"
    echo "   podman exec $CONTAINER_NAME ss -tlnp | grep 6666"
fi

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "Container:      $CONTAINER_NAME"
echo "Home directory: $CONTAINER_HOME"
echo ""
echo "To connect with Neovide, run:"
echo "  neovide --server 127.0.0.1:6666"
echo ""
echo "To enter the container, run:"
echo "  distrobox enter $CONTAINER_NAME"
echo ""
