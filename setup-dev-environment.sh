#!/bin/bash

# --- Define user and container names for clarity ---
USERNAME="$USER"
CONTAINER="fedora-development"
HOST_XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
HOST_WAYLAND_DISPLAY=$WAYLAND_DISPLAY

# --- Pre-flight checks and cleanup ---

# Check if the container exists. Its removal is mandatory to proceed.
if podman container exists "$CONTAINER"; then
    read -p "Container '$CONTAINER' already exists. It must be removed to proceed. Continue? (y/N) " -r
    echo # Move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing container '$CONTAINER'..."
        podman rm -f "$CONTAINER"
    else
        echo "Setup aborted by user. The existing container was not removed."
        exit 1
    fi
fi

# Check if the volume exists and ask if the user wants a fresh installation.
if podman volume exists "$CONTAINER"; then
    read -p "Volume '$CONTAINER' already exists. Do you want to remove it for a fresh install? (y/N) " -r
    echo # Move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing volume '$CONTAINER' for a clean slate..."
        podman volume rm -f "$CONTAINER"
    else
        echo "Keeping the existing volume '$CONTAINER'."
    fi
fi

# --- Create new environment ---
echo "Creating new volume and container..."

# Create the volume only if it doesn't exist (i.e., it's a first run or was just removed).
if ! podman volume exists "$CONTAINER"; then
    podman volume create "$CONTAINER"
fi

podman run -d --name fedora-development-wayland \
  --userns=keep-id \
  --group-add keep-groups \
  --security-opt label=disable \
  -e WAYLAND_DISPLAY=$HOST_WAYLAND_DISPLAY \
  -e XDG_RUNTIME_DIR=$CONTAINER_XDG_RUNTIME_DIR \
  -v $HOST_XDG_RUNTIME_DIR:$CONTAINER_XDG_RUNTIME_DIR \
  fedora:latest \
  sleep infinity

# --- Run setup commands as root ---
echo "Running setup as root..."

# Update system
podman exec -u root "$CONTAINER" dnf update -y

# Install all necessary dependencies
podman exec -u root "$CONTAINER" dnf install -y git zsh curl util-linux-user unzip fontconfig nvim tmux tzdata lm_sensors keychain @development-tools

# Install locale information and set it system-wide
podman exec -u root "$CONTAINER" sh -c 'dnf install -y glibc-langpack-en && echo "LANG=en_US.UTF-8" > /etc/locale.conf'

# Set the timezone to São Paulo / Brazil
podman exec -u root "$CONTAINER" ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Install JetBrains Mono Nerd Font
echo "Installing Nerd Fonts..."
podman exec -u root "$CONTAINER" sh -c '
curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
unzip /tmp/fonts.zip -d /usr/local/share/fonts/JetBrainsMonoNF
rm /tmp/fonts.zip
fc-cache -fv
'

# Configure user permissions and home directory
podman exec -u root "$CONTAINER" sh -c "echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USERNAME"
podman exec -u root "$CONTAINER" cp -rT /etc/skel/ "/home/$USERNAME/"
podman exec -u root "$CONTAINER" chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/"
podman exec -u root "$CONTAINER" usermod -d "/home/$USERNAME" -s /usr/bin/zsh "$USERNAME"

# --- Run setup commands as the user ---
echo "Configuring user environment..."
# We use zsh -c '...' here so that sourcing sdkman-init.sh works correctly
podman exec -u "$USERNAME" -w "/home/$USERNAME" "$CONTAINER" /bin/zsh -c '
# --- Create standard directories first ---
mkdir -p .local/{share,state,bin} .config

# --- Clone Neovim configuration ---
# This removes the old config to ensure it is always the latest version from git
rm -rf .config/nvim
git clone https://github.com/andreluisos/nvim.git .config/nvim

# --- Download Tmux configuration ---
mkdir -p .config/tmux
curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/ptyxis/main/tmux
curl -fLo .config/tmux/tmux_status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/ptyxis/main/tmux_status.sh
chmod +x .config/tmux/tmux_status.sh

# Check if TPM is already installed before cloning
if [ ! -d ".tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm .tmux/plugins/tpm
fi

# --- Force reinstallation of Oh My Zsh ---
echo "Preparing for Oh My Zsh reinstallation..."
# Remove existing directory to ensure a clean install
if [ -d "$HOME/.oh-my-zsh" ]; then
    rm -rf "$HOME/.oh-my-zsh"
fi
# Remove existing .zshrc so the installer creates a fresh one
if [ -f "$HOME/.zshrc" ]; then
    rm -f "$HOME/.zshrc"
fi
echo "Installing Oh My Zsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# --- Install Zsh plugins ---
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
# Ensure the custom plugins directory exists before cloning into it.
mkdir -p "${ZSH_CUSTOM}/plugins"

# Clone all plugins (will be a fresh clone since parent dir was removed)
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM}/plugins/zsh-history-substring-search

# --- Configure .zshrc ---
# These sed commands are safe to re-run on the fresh .zshrc file
sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" .zshrc
sed -i "s/# export PATH=\$HOME\/bin:\/usr\/local\/bin:\$PATH/export PATH=\$HOME\/bin:\/usr\/local\/bin:\$PATH/g" .zshrc
# We can add checks to prevent adding duplicate lines to .zshrc
grep -qxF "autoload -U compinit && compinit" .zshrc || echo "autoload -U compinit && compinit" >> .zshrc
grep -qF "keychain --eval" .zshrc || echo "\\n# Load SSH keys\\neval \$(keychain --eval --quiet \$(grep -srlF -e \"PRIVATE KEY\" ~/.ssh))" >> .zshrc
mkdir -p .ssh

# --- Force reinstallation of SDKMAN! ---
echo "Preparing for SDKMAN! reinstallation..."
# Remove existing directory to ensure a clean install
if [ -d "$HOME/.sdkman" ]; then
    rm -rf "$HOME/.sdkman"
fi
echo "Installing SDKMAN!..."
curl -s "https://get.sdkman.io" | bash

# Source SDKMAN! to use it immediately in this script
source "$HOME/.sdkman/bin/sdkman-init.sh"

echo "Installing latest GraalVM CE..."
# Find the latest identifier for GraalVM Community Edition
GRAALVM_IDENTIFIER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " ")
# This command is safe; SDKMAN will not reinstall if it already exists
sdk install java $GRAALVM_IDENTIFIER

echo "Installing latest Gradle..."
# Let SDKMAN install the latest version automatically, which is more robust
sdk install gradle
'

echo "Dev environment setup complete!"
