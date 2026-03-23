#!/bin/bash
# Phase 2: User-level configuration for Andre's DevBox
# This script runs INSIDE the container as the user 'andreluis'
# Usage: setup-user-env.sh [--skip]

set -e

# Parse arguments
SKIP_OVERWRITE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip|-s)
            SKIP_OVERWRITE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip]"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "DevBox User Environment Setup"
echo "=========================================="

# --- 1. Directory Structure ---
echo "==> Creating standard directories..."
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/Documents/projects"

# --- 2. SSH & Git Configuration ---
echo "==> Configuring SSH and Git for Agent Forwarding..."

# Ensure ~/.ssh exists with correct permissions
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Add GitHub to known_hosts if not already present
if ! grep -q "github.com" "$HOME/.ssh/known_hosts" 2>/dev/null; then
    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
fi

# Create SSH config for agent forwarding (overwrite to ensure clean state)
cat > "$HOME/.ssh/config" << EOF
# DevBox SSH Config
Host *
    ForwardAgent yes
    StrictHostKeyChecking accept-new
EOF
chmod 600 "$HOME/.ssh/config"

# Configure Git to use the SSH bridge and rewrite HTTPS to SSH automatically
git config --global user.email "zandreluisos@gmail.com"
git config --global user.name "andreluis"
git config --global url."git@github.com:".insteadOf "https://github.com/"
# Remove any previous core.sshCommand that might interfere with agent forwarding
git config --global --unset core.sshCommand 2>/dev/null || true

# --- 3. Neovim Configuration (The Private Clone) ---
echo "==> Setting up Neovim configuration..."
# Ensure SSH_AUTH_SOCK is set (distrobox might not inherit it properly)
export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-/run/user/$(id -u)/gcr/ssh}"

if [ -d "$HOME/.config/nvim" ]; then
    if [ "$SKIP_OVERWRITE" = true ]; then
        echo "   --skip specified: Keeping existing nvim config, pulling latest changes..."
        cd "$HOME/.config/nvim" && git pull && cd -
    else
        echo "   Removing existing nvim config for fresh clone..."
        rm -rf "$HOME/.config/nvim"
        echo "   Cloning private nvim config from GitHub..."
        git clone git@github.com:andreluisos/nvim.git "$HOME/.config/nvim"
    fi
else
    echo "   Cloning private nvim config from GitHub..."
    # This uses the SSH agent bridge inherited from the master setup.sh
    git clone git@github.com:andreluisos/nvim.git "$HOME/.config/nvim"
fi

# --- 4. Development Tools (SDKMAN! & Rust) ---
# Note: These usually require interactive shell, so we source them if they exist
if [ -d "$HOME/.sdkman" ]; then
    echo "==> SDKMAN! already installed."
else
    echo "==> Installing SDKMAN! for Java/Kotlin development..."
    curl -s "https://get.sdkman.io?rcupdate=false" | bash
fi

if [ -d "$HOME/.cargo" ]; then
    echo "==> Rust/Cargo already installed."
else
    echo "==> Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi

# --- 5. Tmux Configuration ---
echo "==> Setting up Tmux configuration..."
mkdir -p "$HOME/.config/tmux"

if [ -f "$HOME/tmux.conf" ]; then
    cp "$HOME/tmux.conf" "$HOME/.config/tmux/tmux.conf"
    rm "$HOME/tmux.conf"
    echo "   Tmux config installed"
fi

if [ -f "$HOME/status.sh" ]; then
    cp "$HOME/status.sh" "$HOME/.config/tmux/status.sh"
    chmod +x "$HOME/.config/tmux/status.sh"
    rm "$HOME/status.sh"
    echo "   Status bar script installed"
fi

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "   Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
    echo "   Tmux Plugin Manager already installed."
fi

# --- 6. Shell Customization (Zsh) ---
echo "==> Finalizing Zsh configuration..."
# Ensure the SSH_AUTH_SOCK export we added in setup.sh remains at the TOP of .zshrc
# (The master script handles the 'export' line, we just ensure .zshrc exists)
touch "$HOME/.zshrc"

# Configure tmux to use custom config location
if ! grep -qF "alias tmux=" "$HOME/.zshrc"; then
    cat >> "$HOME/.zshrc" << 'TMUX_EOF'

# Tmux configuration
alias tmux='tmux -f "$HOME/.config/tmux/tmux.conf"'
TMUX_EOF
    echo "   Tmux alias added to .zshrc"
fi

echo ""
echo "=========================================="
echo "✅ Phase 2 Complete: User Environment Ready"
echo "=========================================="
