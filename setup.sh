#!/bin/bash

# This script automates the setup of a Linux development environment.
# It configures GNOME settings, sets up Ptyxis, installs fonts,
# sets environment variables, and generates Distrobox configuration.

set -e # Exit immediately if a command exits with a non-zero status

echo "Starting environment setup..."

# --- 0. Pre-Checks & Variables ---
CONFIG_DIR="$HOME/.config/distrobox"
CONFIG_FILE="$CONFIG_DIR/distrobox.ini"

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

# Try to set palette for the current profile
if [ -n "$PTYXIS_PROFILE" ]; then
    gsettings set "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$PTYXIS_PROFILE/" palette 'gnome' || echo "Warning: Could not set Ptyxis palette."
fi

# CSS padding fix
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

# --- 5. Distrobox Configuration ---
echo ">>> Creating Distrobox configuration directory: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

echo ">>> Creating container storage directories..."
mkdir -p "$HOME/Documents/containers/dev"
mkdir -p "$HOME/Documents/containers/esp"

echo ">>> Writing configuration to $CONFIG_FILE..."

# Note: Variables $HOME and $USER are expanded NOW. 
# This correctly hardcodes the user into the ini file.
cat <<EOF > "$CONFIG_FILE"
[dev]
image=registry.fedoraproject.org/fedora-toolbox:latest
home=$HOME/Documents/containers/dev
additional_packages="git zsh neovim tmux gcc gcc-c++ openssl-devel systemd-devel pkg-config curl"
init_hooks=su - $USER -c "curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/bootstrap.sh | bash"

[esp-rust]
image=registry.fedoraproject.org/fedora-toolbox:latest
home=$HOME/Documents/containers/esp
additional_flags="--privileged"
additional_packages="git zsh neovim tmux gcc gcc-c++ clang openssl-devel pkg-config systemd-devel python3 python3-pip libudev-devel"
init_hooks=su - $USER -c "curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/bootstrap.sh | bash"
EOF

echo ">>> Success! Content of generated file:"
echo "---------------------------------------------------"
cat "$CONFIG_FILE"
echo "---------------------------------------------------"

echo "🎉 Setup complete! Please log out and back in for all changes to take effect."
