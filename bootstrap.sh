#!/bin/bash
# ~/bootstrap.sh
# ------------------------------------------------------------------
# Provisioning Script for Toolbox Dev Environments
# Handles: Package installation and ESP32 Toolchains.
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

# --- 4. EMBEDDED RUST (Exclusive to 'esp-rust' container) ---

if [[ "$HOSTNAME" == "esp-rust" ]]; then
    echo ">>> [EMBEDDED] Detected 'esp-rust' container. Starting Specialized Setup..."

    # A. Install cargo-binstall (Essential for speed)
    if ! command -v cargo-binstall &> /dev/null; then
        echo ">>> [EMBEDDED] Installing cargo-binstall..."
        curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
    fi

    # B. Install espup (Toolchain Installer)
    if ! command -v espup &> /dev/null; then
        echo ">>> [EMBEDDED] Installing espup..."
        cargo binstall -y espup
    fi

    # C. Run espup install (Downloads Clang, GCC for Xtensa, etc)
    if [ ! -f "$HOME/export-esp.sh" ]; then
        echo ">>> [EMBEDDED] Running espup install (this downloads the compilers)..."
        espup install
    fi

    # D. Install Helper Tools (Flash, Generate, Proxy)
    # Using binstall here saves ~15 minutes of compile time
    echo ">>> [EMBEDDED] Installing espflash, cargo-generate, ldproxy..."
    cargo binstall -y cargo-generate espflash ldproxy

    echo ">>> [EMBEDDED] Environment Ready."
else
    echo ">>> [BOOTSTRAP] Skipping Embedded Setup (Hostname is not 'esp-rust')"
fi

# --- 5. FINALIZATION ---
echo ">>> [BOOTSTRAP] Setup Complete! Please restart your shell or type 'zsh'."
