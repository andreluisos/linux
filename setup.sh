#!/bin/bash

# This script automates the setup of a Linux development environment.
# It configures GNOME settings, sets up environment variables,
# downloads utility scripts, asks for confirmation, runs them, and creates aliases.

echo "Starting environment setup..."

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
echo "GNOME settings applied."

# --- Environment Variable Setup ---
# Appends environment variables to the user's .profile file.
# This ensures they are loaded on every login.
echo "Setting up environment variables in .profile..."
{
  echo '' # Add a newline for separation
  echo '# --- Custom Environment Variables ---'
  echo 'export EDITOR="vi"'
} >> "$HOME/.profile"
echo "Environment variables added."

# Install JetBrains Mono Nerd Font
echo "Installing Nerd Fonts..."
mkdir -p "$HOME/.local/share/fonts"
curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNF"
unzip /tmp/fonts.zip -d "$HOME/.local/share/fonts/JetBrainsMonoNF"
rm /tmp/fonts.zip
fc-cache -fv

# --- Script Downloads ---
# Downloads the necessary scripts from the specified GitHub repository.
# It places them in the user's home directory and makes them executable.
echo "Downloading utility scripts..."
mkdir -p "$HOME/.scripts"
wget -O "$HOME/.scripts/build-ghostty.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/build-ghostty.sh
wget -O "$HOME/.scripts/create-ghostty-shortcut.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/create-ghostty-shortcut.sh
wget -O "$HOME/.scripts/setup-dev-environment.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/setup-dev-environment.sh

# Make the downloaded scripts executable
chmod +x "$HOME/.scripts/build-ghostty.sh"
chmod +x "$HOME/.scripts/create-ghostty-shortcut.sh"
chmod +x "$HOME/.scripts/setup-dev-environment.sh"
echo "Scripts downloaded and made executable."

# --- Script Execution Confirmation ---
echo "Please confirm which scripts you would like to run."
read -p "Run build-ghostty.sh? (y/n): " run_build
read -p "Run create-ghostty-shortcut.sh? (y/n): " run_shortcut
read -p "Run setup-dev-environment.sh? (y/n): " run_dev_env

# --- Running Downloaded Scripts ---
echo "Running selected setup scripts..."
if [[ "$run_dev_env" =~ ^[Yy]$ ]]; then
    echo "Executing setup-dev-environment.sh..."
    "$HOME/.scripts/setup-dev-environment.sh"
else
    echo "Skipping setup-dev-environment.sh."
fi

if [[ "$run_build" =~ ^[Yy]$ ]]; then
    echo "Executing build-ghostty.sh..."
    "$HOME/.scripts/build-ghostty.sh"
else
    echo "Skipping build-ghostty.sh."
fi

if [[ "$run_shortcut" =~ ^[Yy]$ ]]; then
    echo "Executing create-ghostty-shortcut.sh..."
    "$HOME/.scripts/create-ghostty-shortcut.sh"
else
    echo "Skipping create-ghostty-shortcut.sh."
fi
echo "Scripts execution phase complete."


# --- Ghostty Configuration ---
# Creates the necessary directory and downloads the ghostty config file.
echo "Downloading ghostty configuration..."
mkdir -p "$HOME/.config/ghostty"
wget -O "$HOME/.config/ghostty/config" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/ghostty
echo "Ghostty configuration downloaded."

# --- Command Alias Setup ---
# Creates aliases in .profile for the downloaded scripts for easy access.
echo "Creating command aliases in .profile..."
{
  echo '' # Add a newline for separation
  echo '# --- Custom Command Aliases ---'
  echo 'alias build-ghostty="$HOME/build-ghostty.sh"'
  echo 'alias set-dev-env="$HOME/setup-dev-environment.sh"'
} >> "$HOME/.profile"
echo "Command aliases created."

# --- Source the profile to apply changes ---
echo "Applying changes to the current session..."
# shellcheck source=/dev/null
source "$HOME/.profile"

echo "Setup complete! Your profile has been updated and sourced. For all changes to take full effect, you may need to log out and log back in."
