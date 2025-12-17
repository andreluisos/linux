#!/bin/bash
# ~/distrobox-bootstrap.sh
# ------------------------------------------------------------------
# Universal Provisioning Script for Distrobox Dev Environments
# Handles: Dotfiles, Zsh, SDKMAN, Rust, and ESP32 Toolchains.
# ------------------------------------------------------------------

set -e # Exit immediately if a command exits with a non-zero status

# --- 0. IDEMPOTENCY CHECK ---
if [ -f "$HOME/.provisioning_complete" ]; then
    echo ">>> Container already provisioned. Skipping bootstrap."
    exit 0
fi

echo ">>> [BOOTSTRAP] Starting provisioning for user: $USER (Host: $HOSTNAME)"

# --- 1. CORE DIRECTORIES ---
mkdir -p "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.config" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# --- 2. SSH KEYS FIX ---
# Fix permissions for keys mapped from host
if [ -f "$HOME/.ssh/id_ed25519" ] || [ -f "$HOME/.ssh/id_rsa" ]; then
    chmod 600 "$HOME/.ssh/id_"*
    chmod 644 "$HOME/.ssh/id_"*.pub 2>/dev/null || true
    echo ">>> [SSH] Fixed key permissions."
fi

# --- 3. SYSTEM TOOLS ---

# > LAZYGIT
if [ ! -f "$HOME/.local/bin/lazygit" ]; then
    echo ">>> [INSTALL] Lazygit..."
    LG_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    mv lazygit "$HOME/.local/bin/"
    rm lazygit.tar.gz
fi

# --- 4. DOTFILES & CONFIG ---

# > NEOVIM
if [ ! -d "$HOME/.config/nvim" ]; then
    echo ">>> [CONFIG] Cloning Neovim config..."
    git clone https://github.com/andreluisos/nvim.git "$HOME/.config/nvim"
else
    echo ">>> [CONFIG] Updating Neovim config..."
    git -C "$HOME/.config/nvim" pull
fi

# > TMUX
echo ">>> [CONFIG] Setting up Tmux..."
mkdir -p "$HOME/.config/tmux"
curl -fLo "$HOME/.config/tmux/tmux.conf" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
curl -fLo "$HOME/.config/tmux/status.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
chmod +x "$HOME/.config/tmux/status.sh"

# > TPM (Tmux Plugin Manager)
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

# --- 5. SHELL SETUP (ZSH & OMZ) ---

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo ">>> [SHELL] Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# > ZSH PLUGINS
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM}/plugins"

declare -A PLUGINS=(
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
    ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
    ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search"
)

for plugin in "${!PLUGINS[@]}"; do
    if [ ! -d "${ZSH_CUSTOM}/plugins/$plugin" ]; then
        echo ">>> [SHELL] Installing plugin: $plugin"
        git clone "${PLUGINS[$plugin]}" "${ZSH_CUSTOM}/plugins/$plugin"
    fi
done

# > .ZSHRC CONFIGURATION
echo ">>> [SHELL] Configuring .zshrc..."
[ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak"

# Activate plugins
sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" "$HOME/.zshrc"

# Append custom config block if not present
if ! grep -q "DISTROBOX_CUSTOM_CONFIG" "$HOME/.zshrc"; then
cat << 'EOF' >> "$HOME/.zshrc"

# --- DISTROBOX_CUSTOM_CONFIG ---
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/.cargo/bin:$PATH

# SSH Agent (Keychain)
if command -v keychain >/dev/null 2>&1; then
    eval $(keychain --eval --quiet)
fi

# SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# ESP32 / Embedded Rust (Only loads if file exists)
[ -f "$HOME/export-esp.sh" ] && source "$HOME/export-esp.sh"

# Fix Locale
export LANG=en_US.UTF-8
EOF
fi

# --- 6. GENERAL LANGUAGES (For all containers) ---

# > SDKMAN (Java/Gradle)
if [ ! -d "$HOME/.sdkman" ]; then
    echo ">>> [LANG] Installing SDKMAN..."
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    
    echo ">>> [LANG] Installing Java (GraalVM)..."
    GRAAL_VER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " " || true)
    sdk install java "$GRAAL_VER" || true
    sdk install gradle || true
else 
    source "$HOME/.sdkman/bin/sdkman-init.sh"
fi

# > RUST (Rustup)
if ! command -v rustup &> /dev/null; then
    echo ">>> [LANG] Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# --- 7. EMBEDDED RUST (Exclusive to 'esp-rust' container) ---

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

# --- 8. FINALIZATION ---
touch "$HOME/.provisioning_complete"
echo ">>> [BOOTSTRAP] Setup Complete! Please restart your shell or type 'zsh'."
