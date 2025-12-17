#!/bin/bash
# ~/bootstrap.sh
# ------------------------------------------------------------------
# Provisioning Script for Toolbox Dev Environments
# Handles: Package installation only.
# ------------------------------------------------------------------

set -e # Exit immediately if a command exits with a non-zero status

echo ">>> [BOOTSTRAP] Starting provisioning for user: $USER (Host: $HOSTNAME)"

# --- 1. CORE DIRECTORIES ---
mkdir -p "$HOME/.config"

# --- 2. PACKAGE INSTALLATION ---
echo ">>> [PACKAGES] Installing required packages..."
sudo dnf install -y git zsh neovim tmux gcc gcc-c++ openssl-devel systemd-devel pkg-config curl

# --- 3. ESP-SPECIFIC PACKAGES ---
if [[ "$HOSTNAME" == "esp-rust" ]]; then
    echo ">>> [PACKAGES] Installing ESP-specific packages..."
    sudo dnf install -y clang python3 python3-pip libudev-devel
fi

# --- 4. FINALIZATION ---
echo ">>> [BOOTSTRAP] Setup Complete! Please restart your shell or type 'zsh'."
