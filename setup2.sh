#!/bin/bash

# This script automates the setup of a Linux development environment.
# It configures GNOME settings, sets up environment variables,
# downloads utility scripts, asks for confirmation, runs them, and creates aliases.
# It also configures 100% ZRAM if not already present.

echo "Starting environment setup..."

# --- ZRAM Configuration (Requires Sudo) ---
ZRAM_CONF="/etc/systemd/zram-generator.conf"

if [ -f "$ZRAM_CONF" ]; then
    echo "ZRAM configuration already exists at $ZRAM_CONF. Skipping."
else
    echo "Configuring ZRAM (100% RAM)..."
    echo "This step requires sudo privileges to write to /etc/systemd/."
    
    # Write the config file using tee to handle sudo write permissions
    sudo tee "$ZRAM_CONF" > /dev/null <<EOF
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF

    echo "Reloading systemd and activating ZRAM..."
    sudo systemctl daemon-reload
    sudo systemctl restart dev-zram0.swap
    
    echo "ZRAM setup complete."
fi

# --- Terminal Choice ---
echo "Please choose your preferred terminal:"
echo "  1) Ptyxis (Default)"
echo "  2) Wezterm (via Flathub)"
read -p "Enter choice (1 or 2): " term_choice

TERMINAL_CHOICE="ptyxis"
if [[ "$term_choice" == "2" ]]; then
    TERMINAL_CHOICE="wezterm"
fi
echo "Using terminal: $TERMINAL_CHOICE"

# --- GNOME Desktop Configuration ---
echo "Configuring GNOME desktop settings..."
gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>1']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Super>2']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Super>3']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Super>4']"
gsettings set org.gnome.desktop.datetime automatic-timezone true
gsettings set org.gnome.desktop.interface clock-format '24h'
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true
gsettings set org.gnome.nautilus.list-view use-tree-view true
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false

# --- Terminal-Specific Configuration ---
if [[ "$TERMINAL_CHOICE" == "ptyxis" ]]; then
    echo "Configuring Ptyxis..."
    # The profile ID logic was missing in your snippet, assuming 'default' or similar if needed.
    # Note: PTYXIS_PROFILE variable was not defined in source, usually it's a UUID. 
    # Attempting to fetch the default profile UUID if possible, otherwise skipping profile-specific set.
    PTYXIS_PROFILE=$(gsettings get org.gnome.Ptyxis default-profile | tr -d "'")
    
    gsettings set org.gnome.Ptyxis disable-padding true
    gsettings set org.gnome.Ptyxis use-system-font false
    gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font Medium 11'
    
    if [ -n "$PTYXIS_PROFILE" ]; then
        gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$PTYXIS_PROFILE/ palette 'gnome'
    fi

    mkdir -p .config/gtk-4.0
    cat << 'EOF' > .config/gtk-4.0/gtk.css
/* padding for ptyxis */
VteTerminal,
 TerminalScreen,
 vte-terminal {
     padding: 0;
}
EOF
    echo "Ptyxis settings applied."
else
    echo "Installing and configuring Wezterm..."
    flatpak install -y flathub org.wezfurlong.wezterm
    
    mkdir -p "$HOME/.config/wezterm"
    echo "Downloading Wezterm config..."
    wget -O "$HOME/.config/wezterm/wezterm.lua" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/wezterm.lua
    
    echo "Downloading Wezterm status script..."
    wget -O "$HOME/.config/wezterm/status.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
    chmod +x "$HOME/.config/wezterm/status.sh"
    
    echo "Wezterm setup complete."
fi

echo "GNOME settings applied."

# --- Environment Variable Setup ---
echo "Setting up environment variables in .profile..."
{
  echo '' # Add a newline for separation
  echo '# --- Custom Environment Variables ---'
  echo 'export EDITOR="vi"'
} >> "$HOME/.profile"
echo "Environment variables added."

# Install JetBrains Mono Nerd Font
FONT_NAME="JetBrainsMono Nerd Font"
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNF"

echo "Checking for '$FONT_NAME'..."

if fc-list | grep -q "$FONT_NAME"; then
    echo "'$FONT_NAME' is already installed. Skipping download and installation."
else
    echo "'$FONT_NAME' not found. Installing now..."
    mkdir -p "$HOME/.local/share/fonts"
    curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
    mkdir -p "$FONT_DIR"
    unzip -o /tmp/fonts.zip -d "$FONT_DIR" # Added -o to overwrite if partial exists
    rm /tmp/fonts.zip
    fc-cache -fv
    echo "Nerd Fonts installed and cache updated."
fi

# --- Script Downloads ---
echo "Downloading utility scripts..."
mkdir -p "$HOME/.scripts"
wget -O "$HOME/.scripts/create-dev-env-shortcut.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/create-dev-env-shortcut.sh
wget -O "$HOME/.scripts/setup-dev-environment.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/setup-dev-environment.sh

chmod +x "$HOME/.scripts/create-dev-env-shortcut.sh"
chmod +x "$HOME/.scripts/setup-dev-environment.sh"
echo "Scripts downloaded and made executable."

# --- Script Execution Confirmation ---
echo "Please confirm which scripts you would like to run."
read -p "Run create-dev-env-shortcut.sh? (y/n): " run_shortcut
read -p "Run setup-dev-environment.sh? (y/n): " run_dev_env

# --- Running Downloaded Scripts ---
echo "Running selected setup scripts..."
if [[ "$run_dev_env" =~ ^[Yy]$ ]]; then
    echo "Executing setup-dev-environment.sh..."
    "$HOME/.scripts/setup-dev-environment.sh"
else
    echo "Skipping setup-dev-environment.sh."
fi

if [[ "$run_shortcut" =~ ^[Yy]$ ]]; then
    echo "Executing create-dev-env-shortcut.sh..."
    "$HOME/.scripts/create-dev-env-shortcut.sh" "$TERMINAL_CHOICE"
else
    echo "Skipping create-dev-env-shortcut.sh."
fi
echo "Scripts execution phase complete."

# --- Command Alias Setup ---
echo "Creating command aliases in .profile..."
{
  echo '' 
  echo '# --- Custom Command Aliases ---'
  echo 'alias set-dev-env="$HOME/.scripts/setup-dev-environment.sh"' # Fixed path to match download location
} >> "$HOME/.profile"
echo "Command aliases created."

# --- Source the profile to apply changes ---
echo "Applying changes to the current session..."
# shellcheck source=/dev/null
source "$HOME/.profile"

echo "Setup complete! Your profile has been updated and sourced."
