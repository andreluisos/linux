#!/bin/bash
set -e

# --- Configuration ---
CONTAINER_NAME="dev"
IMAGE="fedora:latest"
HOME_DIR="$HOME/Documents/containers/$CONTAINER_NAME"
USER_ID=$(id -u)
# The "Source of Truth" for your SSH Agent on the Host
SSH_SOCK_PATH="/run/user/$USER_ID/gcr/ssh"
NVIM_SOCKET="/tmp/nvimsocket"

echo "=========================================="
echo "🚀 Starting DevBox Rebuild for $USER"
echo "=========================================="

# 1. Host Pre-check
if ! ssh-add -l > /dev/null 2>&1; then
    echo "❌ ERROR: No SSH identities found. Run 'ssh-add ~/.ssh/personal' on host."
    exit 1
fi

# 2. Cleanup
distrobox rm $CONTAINER_NAME --force 2>/dev/null || true

# 3. Create Container
# SSH agent forwarding is automatic via SSH_AUTH_SOCK - no key files needed
distrobox create --name $CONTAINER_NAME \
  --image $IMAGE \
  --home "$HOME_DIR" \
  --yes

# 3.5. Copy setup scripts to container home
echo "==> Copying setup scripts to container home..."
cp "$PWD/setup-env.sh" "$HOME_DIR/"
cp "$PWD/setup-user-env.sh" "$HOME_DIR/"
cp "$PWD/tmux.conf" "$HOME_DIR/"
cp "$PWD/status.sh" "$HOME_DIR/"

# 4. Provisioning - Phase 1 (Root)
distrobox enter $CONTAINER_NAME -- sudo "$HOME_DIR/setup-env.sh"

# 5. Provisioning - Phase 2 (User)
# Distrobox automatically forwards SSH_AUTH_SOCK from host
echo "==> Running Phase 2: User Setup ($USER)..."
distrobox enter $CONTAINER_NAME -- "$HOME_DIR/setup-user-env.sh"

# 7. Neovim Service Configuration
mkdir -p ~/.config/systemd/user/
cat > ~/.config/systemd/user/nvim-server.service << EOF
[Unit]
Description=Neovim Headless Server (Distrobox: $CONTAINER_NAME)
After=network.target

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=$SSH_SOCK_PATH
ExecStartPre=/usr/bin/rm -f $NVIM_SOCKET
ExecStart=/usr/bin/distrobox enter $CONTAINER_NAME -- /usr/bin/nvim --headless --listen $NVIM_SOCKET
Restart=always

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable nvim-server.service
systemctl --user restart nvim-server.service

# 8. Create GNOME Keyboard Shortcuts
echo "==> Creating GNOME keyboard shortcuts..."

# Detect binary paths (use absolute paths for GNOME shortcuts)
DISTROBOX_BIN=$(command -v distrobox || echo "/usr/bin/distrobox")
PTYXIS_BIN=$(command -v ptyxis || echo "/usr/bin/ptyxis")
NEOVIDE_BIN=$(command -v neovide || echo "/usr/bin/neovide")

# Define commands
CMD_TERM="$PTYXIS_BIN --new-window -- $DISTROBOX_BIN enter $CONTAINER_NAME -- /bin/zsh -l -c 'cd && tmux -u'"
CMD_NEOVIDE="$NEOVIDE_BIN --server $NVIM_SOCKET"

# Function to add a GNOME shortcut
add_gnome_shortcut() {
    local name="$1"
    local command="$2"
    local binding="$3"

    local base_path="org.gnome.settings-daemon.plugins.media-keys"
    local keybinding_list_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

    # Get current list
    local current_list=$(gsettings get $base_path custom-keybindings)

    # Check if shortcut already exists
    local existing_paths=$(echo "$current_list" | grep -o "'[^']*'" | tr -d "'")
    for path in $existing_paths; do
        local existing_name=$(gsettings get "$base_path.custom-keybinding:$path" name 2>/dev/null | tr -d "'")
        if [[ "$existing_name" == "$name" ]]; then
            echo "   Shortcut '$name' already exists. Skipping."
            return 0
        fi
    done

    # Find next available index
    local last_index=$(echo "$current_list" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -1)
    
    local new_index=0
    local new_list=""
    
    if [[ -z "$last_index" ]]; then
        new_index=0
        new_list="['$keybinding_list_path/custom$new_index/']"
    else
        new_index=$((last_index + 1))
        if [[ "$current_list" == "@as []" ]]; then
            new_list="['$keybinding_list_path/custom$new_index/']"
        else
            new_list=${current_list/]/", '$keybinding_list_path/custom$new_index/']"}
        fi
    fi

    local new_path="$keybinding_list_path/custom$new_index/"

    # Apply settings
    gsettings set $base_path custom-keybindings "$new_list"
    gsettings set "$base_path.custom-keybinding:$new_path" name "$name"
    gsettings set "$base_path.custom-keybinding:$new_path" command "$command"
    gsettings set "$base_path.custom-keybinding:$new_path" binding "$binding"

    echo "   Created: '$name' → $binding"
}

# Create shortcuts
add_gnome_shortcut "DevBox Terminal" "$CMD_TERM" "<Super>r"
add_gnome_shortcut "DevBox Neovide" "$CMD_NEOVIDE" "<Super>t"

echo ""
echo "✅ DevBox Provisioned Successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Container: $CONTAINER_NAME"
echo "🔧 Neovim Service: Active (systemd)"
echo "⌨️  Keyboard Shortcuts:"
echo "   • Super+T → Launch Neovide GUI"
echo "   • Super+R → Open terminal in container"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Manual commands:"
echo "  distrobox enter $CONTAINER_NAME"
echo "  neovide --server $NVIM_SOCKET"
