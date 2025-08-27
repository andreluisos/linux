#!/bin/bash

# --- Clean up previous environment ---
echo "🧹 Cleaning up old container and volume..."
podman rm -f development && podman volume rm fedora-development

# --- Create new environment ---
echo "📦 Creating new volume and container..."
podman volume create fedora-development
podman run -d --name development \
--userns=keep-id \
-v fedora-development:/home/$USER:z \
registry.fedoraproject.org/fedora-toolbox:latest \
sleep infinity

# --- Define user and container names for clarity ---
USERNAME="andreluis"
CONTAINER="development"

# --- Run setup commands as root ---
echo "🔧 Running setup as root (installing tools, fonts, setting user)..."
# Install all necessary dependencies
podman exec -u root "$CONTAINER" dnf install -y git zsh curl util-linux-user unzip fontconfig nvim tmux

# Install JetBrains Mono Nerd Font
echo "✅ Installing Nerd Fonts..."
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
echo "🧑 Configuring user environment (Neovim, Oh My Zsh, SDKMAN!, etc.)..."
# We use zsh -c '...' here so that sourcing sdkman-init.sh works correctly
podman exec -u "$USERNAME" -w "/home/$USERNAME" "$CONTAINER" /bin/zsh -c '
# --- Create standard directories first ---
mkdir -p .local/{share,state,bin} .config

# --- Clone Neovim configuration ---
rm -rf .config/nvim
git clone https://github.com/andreluisos/nvim.git .config/nvim

# --- Download Tmux configuration ---
mkdir -p .config/tmux
curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux.conf

# --- Install Oh My Zsh non-interactively ---
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# --- Install Zsh plugins ---
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM}/plugins/zsh-history-substring-search

# --- Configure .zshrc ---
sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" .zshrc
echo "autoload -U compinit && compinit" >> .zshrc
sed -i "s/# export PATH=\$HOME\/bin:\/usr\/local\/bin:\$PATH/export PATH=\$HOME\/bin:\/usr\/local\/bin:\$PATH/g" .zshrc

# --- Install SDKMAN! and GraalVM ---
echo "Installing SDKMAN!..."
curl -s "https://get.sdkman.io" | bash

# Source SDKMAN! to use it immediately in this script
source "$HOME/.sdkman/bin/sdkman-init.sh"

echo "Installing latest GraalVM CE..."
# Find the latest identifier for GraalVM Community Edition
GRAALVM_IDENTIFIER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " ")

# Install and set as default
sdk install java $GRAALVM_IDENTIFIER
'

echo "🎉 Setup complete! Entering the container with your new Zsh shell..."

# --- Enter the new environment with a Zsh login shell, starting in the home directory ---
podman exec -it -w "/home/$USERNAME" "$CONTAINER" /bin/zsh -l
