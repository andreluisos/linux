#!/bin/bash

# This script automates the setup of a Linux development environment.
# It configures GNOME settings, sets up Ptyxis, installs fonts,
# sets environment variables, and installs development tools in shared home.

set -e # Exit immediately if a command exits with a non-zero status

echo "Starting environment setup..."

# --- 0. Pre-Checks & Variables ---
# Get current Ptyxis profile ID if it exists, otherwise default to a safe value
if command -v gsettings &>/dev/null; then
    PTYXIS_PROFILE=$(gsettings get org.gnome.Ptyxis default-profile 2>/dev/null | tr -d "'")
    [ -z "$PTYXIS_PROFILE" ] && PTYXIS_PROFILE="default"
fi

# --- 1. GNOME Desktop Configuration ---
echo "Configuring GNOME desktop settings..."

# General Interface
gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.interface clock-format '24h'
gsettings set org.gnome.desktop.datetime automatic-timezone true

# Window Manager
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>1']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Super>2']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Super>3']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Super>4']"

# --- Custom Keyboard Shortcuts (<Super>t for Ptyxis) ---
echo "Setting custom shortcut <Super>t for Ptyxis..."
KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$KEY_PATH']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEY_PATH name "Ptyxis Terminal"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEY_PATH command "ptyxis --new-window"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEY_PATH binding "<Super>t"

# Nautilus (Files)
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
gsettings set org.gnome.nautilus.list-view use-tree-view true
gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true

# Power
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false

# --- 2. Font Installation (JetBrains Mono Nerd Font) ---
FONT_NAME="JetBrainsMono Nerd Font"
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNF"

echo "Checking for '$FONT_NAME'..."
if fc-list | grep -q "$FONT_NAME"; then
    echo "✅ '$FONT_NAME' is already installed."
else
    echo "📥 Installing '$FONT_NAME'..."
    mkdir -p "$HOME/.local/share/fonts"
    curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
    mkdir -p "$FONT_DIR"
    unzip -o /tmp/fonts.zip -d "$FONT_DIR" > /dev/null
    rm /tmp/fonts.zip
    fc-cache -fv > /dev/null
    echo "✅ Nerd Fonts installed."
fi

# --- 3. Ptyxis Configuration ---
echo "Configuring Ptyxis..."
gsettings set org.gnome.Ptyxis disable-padding true
gsettings set org.gnome.Ptyxis use-system-font false
gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font Medium 11'

if [ -n "$PTYXIS_PROFILE" ]; then
    gsettings set "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$PTYXIS_PROFILE/" palette 'gnome' || echo "Warning: Could not set Ptyxis palette."
fi

mkdir -p "$HOME/.config/gtk-4.0"
cat << 'EOF' > "$HOME/.config/gtk-4.0/gtk.css"
/* padding for ptyxis */
VteTerminal,
TerminalScreen,
vte-terminal {
    padding: 0;
}
EOF
echo "✅ Ptyxis settings applied."

# --- 4. Environment Variables ---
echo "Setting up environment variables..."
if ! grep -q "export EDITOR=\"vi\"" "$HOME/.profile"; then
    echo '' >> "$HOME/.profile"
    echo '# --- Custom Environment Variables ---' >> "$HOME/.profile"
    echo 'export EDITOR="vi"' >> "$HOME/.profile"
    echo "✅ Added EDITOR variable to .profile"
else
    echo "✅ Environment variables already present."
fi

# --- 5. Neovim Configuration ---
if [ ! -d "$HOME/.config/nvim" ]; then
    echo "📥 Cloning Neovim configuration..."
    git clone https://github.com/andreluisos/nvim.git "$HOME/.config/nvim"
    echo "✅ Neovim configuration installed."
else
    echo "✅ Neovim configuration already present."
fi

# --- 6. Zsh Setup ---
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "📥 Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    echo "✅ Oh My Zsh installed."
else
    echo "✅ Oh My Zsh already installed."
fi

# Install Zsh plugins
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
        echo "📥 Installing Zsh plugin: $plugin"
        git clone "${PLUGINS[$plugin]}" "${ZSH_CUSTOM}/plugins/$plugin"
    fi
done
echo "✅ Zsh plugins installed."

# Configure .zshrc
if [ -f "$HOME/.zshrc" ]; then
    # Activate plugins
    if grep -q "plugins=(git)" "$HOME/.zshrc"; then
        sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" "$HOME/.zshrc"
        echo "✅ Zsh plugins activated in .zshrc"
    fi
    
    # Add custom config block if not present
    if ! grep -q "TOOLBOX_CUSTOM_CONFIG" "$HOME/.zshrc"; then
        cat << 'EOF' >> "$HOME/.zshrc"

# --- TOOLBOX_CUSTOM_CONFIG ---
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/.cargo/bin:$PATH

# SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Rust Cargo
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ESP32 / Embedded Rust (Only loads if file exists)
[ -f "$HOME/export-esp.sh" ] && source "$HOME/export-esp.sh"

# Fix Locale
export LANG=en_US.UTF-8

# Bootstrap alias
alias bootstrap-dev='sh -c "$(curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/bootstrap.sh)"'
EOF
        echo "✅ Custom configuration added to .zshrc"
    else
        echo "✅ Custom configuration already present in .zshrc"
    fi
fi

# --- 7. SDKMAN Installation ---
if [ ! -d "$HOME/.sdkman" ]; then
    echo "📥 Installing SDKMAN..."
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    
    echo "📥 Installing Java (GraalVM)..."
    GRAAL_VER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " " || true)
    if [ -n "$GRAAL_VER" ]; then
        sdk install java "$GRAAL_VER" || true
    fi
    
    echo "📥 Installing Gradle..."
    sdk install gradle || true
    echo "✅ SDKMAN, Java, and Gradle installed."
else
    echo "✅ SDKMAN already installed."
fi

# --- 8. Rust Installation ---
if ! command -v rustup &> /dev/null; then
    echo "📥 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo "✅ Rust installed."
else
    echo "✅ Rust already installed."
fi

# --- 9. Lazygit Installation ---
if [ ! -f "$HOME/.local/bin/lazygit" ]; then
    echo "📥 Installing Lazygit..."
    mkdir -p "$HOME/.local/bin"
    LG_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
    tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
    mv /tmp/lazygit "$HOME/.local/bin/"
    rm /tmp/lazygit.tar.gz
    echo "✅ Lazygit installed."
else
    echo "✅ Lazygit already installed."
fi

# --- 10. Tmux Configuration ---
echo "📥 Setting up Tmux configuration..."
mkdir -p "$HOME/.config/tmux"
curl -fLo "$HOME/.config/tmux/tmux.conf" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
curl -fLo "$HOME/.config/tmux/status.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
chmod +x "$HOME/.config/tmux/status.sh"
echo "✅ Tmux configuration updated."

# --- 11. TPM (Tmux Plugin Manager) ---
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "📥 Installing TPM (Tmux Plugin Manager)..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    echo "✅ TPM installed."
else
    echo "✅ TPM already installed."
fi

# --- 12. ESP Tools Installation ---
echo "Setting up ESP tools..."

# A. Install cargo-binstall (Essential for speed)
if ! command -v cargo-binstall &> /dev/null; then
    echo "📥 Installing cargo-binstall..."
    curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
    echo "✅ cargo-binstall installed."
else
    echo "✅ cargo-binstall already installed."
fi

# B. Install espup (Toolchain Installer)
if ! command -v espup &> /dev/null; then
    echo "📥 Installing espup..."
    cargo binstall -y espup
    echo "✅ espup installed."
else
    echo "✅ espup already installed."
fi

# C. Run espup install (Downloads Clang, GCC for Xtensa, etc)
if [ ! -f "$HOME/export-esp.sh" ]; then
    echo "📥 Running espup install (this downloads the compilers)..."
    espup install
    echo "✅ espup install completed."
else
    echo "✅ ESP toolchain already installed."
fi

# D. Install Helper Tools (Flash, Generate, Proxy)
echo "📥 Installing espflash, cargo-generate, ldproxy..."
cargo binstall -y cargo-generate espflash ldproxy
echo "✅ ESP tools installed."

# --- 13. OpenCode Installation ---
if ! command -v opencode &> /dev/null; then
    echo "📥 Installing OpenCode..."
    curl -fsSL https://opencode.ai/install | bash
    echo "✅ OpenCode installed."
else
    echo "✅ OpenCode already installed."
fi

# Configure OpenCode
echo "📥 Configuring OpenCode..."
mkdir -p "$HOME/.config/opencode"
cat > "$HOME/.config/opencode/opencode.json" << "OPENCODE_EOF"
{
  "$schema": "https://opencode.ai/config.json",
  "lsp": {
    "typescript": { "disabled": true },
    "deno": { "disabled": true },
    "eslint": { "disabled": true },
    "gopls": { "disabled": true },
    "ruby-lsp": { "disabled": true },
    "pyright": { "disabled": true },
    "elixir-ls": { "disabled": true },
    "zls": { "disabled": true },
    "csharp": { "disabled": true },
    "vue": { "disabled": true },
    "rust": { "disabled": true },
    "clangd": { "disabled": true },
    "svelte": { "disabled": true },
    "astro": { "disabled": true },
    "yaml-ls": { "disabled": true },
    "jdtls": { "disabled": true },
    "lua-ls": { "disabled": true },
    "sourcekit-lsp": { "disabled": true },
    "php": { "disabled": true }
  }
}
OPENCODE_EOF
echo "✅ OpenCode configured."

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Create toolboxes manually:"
echo "     toolbox create dev"
echo "     toolbox create esp-rust"
echo "  2. Enter a toolbox:"
echo "     toolbox enter dev"
echo "  3. Run the bootstrap script:"
echo "     bootstrap-dev"
echo ""
echo "Please log out and back in for all changes to take effect."
