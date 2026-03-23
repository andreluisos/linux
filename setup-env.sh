#!/bin/bash
# DevBox Environment Setup Script
# This script sets up a complete development environment in a distrobox container
# Run with: distrobox enter dev -- sudo "$(pwd)/setup-env.sh"

set -e

echo "=========================================="
echo "DevBox Environment Setup"
echo "=========================================="
echo ""

# Get the actual non-root username
if [ "$USER" = "root" ] || [ "$(id -u)" = "0" ]; then
    # Find the non-root user with UID >= 1000
    USERNAME=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
    if [ -z "$USERNAME" ]; then
        echo "Error: Could not determine username"
        exit 1
    fi
else
    USERNAME=${USER:-$(whoami)}
fi

echo "Setting up environment for user: $USERNAME"
echo ""

# ============================================
# PHASE 1: System Updates & Package Installation
# ============================================

echo "==> Updating system packages..."
dnf update -y

echo "==> Adding GitHub CLI repository..."
# Using --overwrite to handle existing repo files on Fedora
dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo -y --overwrite

echo "==> Installing all packages..."
# Installing git and gh together allows dnf to resolve dependencies correctly
dnf install -y \
    git \
    gh \
    zsh \
    curl \
    util-linux-user \
    unzip \
    fontconfig \
    nvim \
    tmux \
    lm_sensors \
    keychain \
    fd-find \
    fzf \
    luarocks \
    wget \
    procps-ng \
    openssl-devel \
    @development-tools \
    rustup \
    podman \
    fuse-overlayfs \
    slirp4netns \
    crun \
    buildah \
    skopeo

echo "==> Configuring rootless podman for nested containers..."
# Configure subuid and subgid ranges for rootless containers
if ! grep -q "^$USERNAME:" /etc/subuid; then
    echo "$USERNAME:100000:65536" >> /etc/subuid
    echo "   Added subuid range for $USERNAME"
else
    echo "   subuid already configured for $USERNAME"
fi

if ! grep -q "^$USERNAME:" /etc/subgid; then
    echo "$USERNAME:100000:65536" >> /etc/subgid
    echo "   Added subgid range for $USERNAME"
else
    echo "   subgid already configured for $USERNAME"
fi

# Enable unprivileged ping (needed for slirp4netns networking)
if [ ! -f /proc/sys/net/ipv4/ping_group_range ] || ! grep -q "0 2147483647" /proc/sys/net/ipv4/ping_group_range 2>/dev/null; then
    echo "0 2147483647" > /proc/sys/net/ipv4/ping_group_range 2>/dev/null || true
fi

# Locale and timezone are automatically inherited from host via distrobox

# ============================================
# PHASE 2: Font Installation
# ============================================

echo "==> Installing JetBrains Mono Nerd Font..."
# Use the determined USERNAME variable from Phase 1
FONT_DIR="/home/$USERNAME/.local/share/fonts/JetBrainsMonoNF"

curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
mkdir -p "$FONT_DIR"

# The -q (quiet) and -o (overwrite) flags prevent interaction
unzip -qo /tmp/fonts.zip -d "$FONT_DIR"
rm /tmp/fonts.zip

# Refresh the font cache for the new user-level path
fc-cache -fv "$FONT_DIR" > /dev/null 2>&1
echo "   Nerd Fonts installed to $FONT_DIR"

# ============================================
# PHASE 3: User Configuration
# ============================================

echo "==> Setting default shell to zsh for $USERNAME..."
ZSH_PATH=$(which zsh 2>/dev/null)

if [ -z "$ZSH_PATH" ]; then
    echo "   Warning: zsh not found, shell will remain unchanged."
else
    # Updates /etc/passwd to make zsh the default entry shell
    usermod -s "$ZSH_PATH" "$USERNAME"
    echo "   Default shell for $USERNAME set to: $ZSH_PATH"
fi

echo ""
echo "=========================================="
echo "Phase 1 Complete: System Setup"
echo "Next: Run setup-user-env.sh as $USERNAME"
echo "=========================================="
