#!/bin/bash

# This script automates the setup of a Linux development environment.
# It configures GNOME settings, sets up environment variables,
# downloads utility scripts, and creates aliases for them.

echo "Starting environment setup..."

# --- GNOME Desktop Configuration ---
echo "Configuring GNOME desktop settings..."
gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false
echo "GNOME settings applied."

# --- Environment Variable Setup ---
# Appends environment variables to the user's .profile file.
# This ensures they are loaded on every login.
echo "Setting up environment variables in .profile..."
{
  echo '' # Add a newline for separation
  echo '# --- Custom Environment Variables ---'
  echo 'export EDITOR="vi"'
  echo 'export DEV_CONTAINER="development"'
} >> "$HOME/.profile"
echo "Environment variables added."

# --- Script Downloads ---
# Downloads the necessary scripts from the specified GitHub repository.
# It places them in the user's home directory and makes them executable.
echo "Downloading utility scripts..."
wget -O "$HOME/build-ghostty.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/build-ghostty.sh
wget -O "$HOME/create-ghostty-shortcut.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/create-ghostty-shortcut.sh
wget -O "$HOME/dev-environment.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/dev-environment.sh

# Make the downloaded scripts executable
chmod +x "$HOME/build-ghostty.sh"
chmod +x "$HOME/create-ghostty-shortcut.sh"
chmod +x "$HOME/dev-environment.sh"
echo "Scripts downloaded and made executable."

# --- Ghostty Configuration ---
# Creates the necessary directory and downloads the ghostty config file.
echo "⚙Downloading ghostty configuration..."
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
  echo 'alias set-dev-env="$HOME/dev-environment.sh"'
} >> "$HOME/.profile"
echo "Command aliases created."

echo "Setup complete! Please run 'source ~/.profile' or log out and log back in for the changes to take effect."

