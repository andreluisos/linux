#!/bin/bash

# --- Define user and host variables ---
USERNAME="$USER"

# --- Get container name from user ---
read -p "Enter the name for the development container (e.g., 'fedora-dev'): " CONTAINER
if [[ -z "$CONTAINER" ]]; then echo "Aborting."; exit 1; fi

# --- Get Host Directory ---
DEFAULT_DIR="$HOME/Documents/containers/$CONTAINER"
echo -e "\nWhere should the container's /home/$USERNAME be mapped on the host?"
read -p "Path (default: $DEFAULT_DIR): " INPUT_DIR
HOST_HOME_DIR="${INPUT_DIR:-$DEFAULT_DIR}"
HOST_HOME_DIR="${HOST_HOME_DIR/#\~/$HOME}"

if [ ! -d "$HOST_HOME_DIR" ]; then
    echo "Creating directory: $HOST_HOME_DIR"
    mkdir -p "$HOST_HOME_DIR"
fi

# --- Check container status and determine action ---
MODE=""
if podman container exists "$CONTAINER"; then
    read -p "Container '$CONTAINER' already exists.
(U)pdate it (run setup inside), (R)ecreate it (delete and start over), or (S)kip? [U/r/s] " -r REPLY
    echo # Move to a new line
    case "$REPLY" in
        [Rr]*)
            MODE="RECREATE"
            ;;
        [Ss]*)
            echo "Skipping. No changes made to '$CONTAINER'."
            exit 0
            ;;
        *)
            MODE="UPDATE"
            echo "Will update '$CONTAINER'..."
            ;;
    esac
else
    read -p "Container '$CONTAINER' does not exist. Create it? [Y/n] " -r REPLY
    echo # Move to a new line
    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        echo "Aborting setup."
        exit 0
    fi
    MODE="CREATE"
    echo "Will create '$CONTAINER'..."
fi


# --- Mode: RECREATE ---
# This block runs only if the user chooses to recreate
if [[ "$MODE" == "RECREATE" ]]; then
    echo "Removing container '$CONTAINER'..."
    podman rm -f "$CONTAINER"

    if podman volume exists "$CONTAINER"; then
        read -p "Volume '$CONTAINER' also exists. Do you want to remove it for a fresh install? (y/N) " -r REPLY_VOL
        echo # Move to a new line
        if [[ "$REPLY_VOL" =~ ^[Yy]$ ]]; then
            echo "Removing volume '$CONTAINTER' for a clean slate..."
            podman volume rm -f "$CONTAINTAINER"
        else
            echo "Keeping the existing volume '$CONTAINER'."
        fi
    fi
fi

# --- Mode: CREATE or RECREATE ---
# This block runs for a new container or a recreated one
if [[ "$MODE" == "CREATE" || "$MODE" == "RECREATE" ]]; then
    echo -e "\n--- Storage Configuration ---"
    echo "1) Host Directory (Bind Mount) - Direct access from host file manager [Default]"
    echo "2) Podman Volume               - Better performance, fully isolated"
    read -p "Choose storage type (1 or 2): " STORAGE_CHOICE

    STORAGE_ARGS=""

    if [[ "$STORAGE_CHOICE" == "2" ]]; then
        # --- Option 2: Podman Volume ---
        echo "Using Podman Volume '$CONTAINER'..."
        
        # Create volume if it doesn't exist
        if ! podman volume exists "$CONTAINER"; then
            podman volume create "$CONTAINER"
        fi
        
        # Volume mount (no :Z needed for internal volumes)
        STORAGE_ARGS="-v $CONTAINER:/home/$USERNAME"
    else
        # --- Option 1: Host Directory (Default) ---
        DEFAULT_DIR="$HOME/Documents/containers/$CONTAINER"
        echo -e "\nWhere should the container's /home/$USERNAME be mapped on the host?"
        read -p "Path (default: $DEFAULT_DIR): " INPUT_DIR
        HOST_HOME_DIR="${INPUT_DIR:-$DEFAULT_DIR}"
        HOST_HOME_DIR="${HOST_HOME_DIR/#\~/$HOME}"

        if [ ! -d "$HOST_HOME_DIR" ]; then
            echo "Creating directory: $HOST_HOME_DIR"
            mkdir -p "$HOST_HOME_DIR"
        fi
        
        # Bind mount with :Z for SELinux support
        STORAGE_ARGS="-v $HOST_HOME_DIR:/home/$USERNAME:Z"
    fi

    # --- Ask for additional container arguments ---
    read -p "Enter any additional arguments for 'podman run' (e.g., '-p 8080:8080'): " ADDITIONAL_ARGS

    echo "Creating container..."
    podman run -d --name $CONTAINER \
      --userns=keep-id \
      --init \
      --group-add keep-groups \
      -p 6000:6000 \
      $STORAGE_ARGS \
      $ADDITIONAL_ARGS \
      fedora:latest \
      sleep infinity
fi

# --- Mode: CREATE, RECREATE, or UPDATE ---
# This block runs in all active modes to provision or update the container

# --- Run setup commands as root ---
echo "Running setup as root in '$CONTAINCOMMA'..."
podman exec -u root "$CONTAINER" dnf update -y
# Added rustup to the install list
podman exec -u root "$CONTAINER" dnf install -y git zsh curl util-linux-user unzip fontconfig nvim tmux tzdata lm_sensors keychain fd fzf luarocks wget procps-ng openssl-devel @development-tools rustup

podman exec -u root "$CONTAINER" sh -c 'dnf install -y glibc-langpack-en && echo "LANG=en_US.UTF-8" > /etc/locale.conf'
podman exec -u root "$CONTAINER" ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Install JetBrains Mono Nerd Font
echo "Installing Nerd Fonts in '$CONTAINER'..."
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



# SSH Keys
echo "Configuring SSH keys..."
podman exec -u root "$CONTAINER" sh -c "mkdir -p /home/$USERNAME/.ssh && chown $USERNAME:$USERNAME /home/$USERNAME/.ssh"
if [ -d "$HOME/.ssh" ]; then
    find "$HOME/.ssh" -maxdepth 1 -type f ! -name "known_hosts" ! -name "config" -exec podman cp {} "$CONTAINER:/home/$USERNAME/.ssh/" \; 2>/dev/null || true
    podman exec -u "$USERNAME" "$CONTAINER" chmod 700 .ssh
    podman exec -u "$USERNAME" "$CONTAINER" sh -c "chmod 600 .ssh/* 2>/dev/null || true"
    podman exec -u "$USERNAME" "$CONTAINER" sh -c "chmod 644 .ssh/*.pub 2>/dev/null || true"
fi

# This variable will be passed into the container
CHMOD_COMMANDS=""
if [ ${#SELECTED_KEYS[@]} -gt 0 ]; then
    echo "Copying selected keys to '$CONTAINER'..."
    for key in "${SELECTED_KEYS[@]}"; do
        # Copy private key
        if [ -f "$HOST_SSH_DIR/$key" ]; then
            podman cp "$HOST_SSH_DIR/$key" "$CONTAINER:/home/$USERNAME/.ssh/$key"
            CHMOD_COMMANDS+="chmod 600 .ssh/$key; "
        fi
        # Copy public key if it exists
        if [ -f "$HOST_SSH_DIR/$key.pub" ]; then
            podman cp "$HOST_SSH_DIR/$key.pub" "$CONTAINER:/home/$USERNAME/.ssh/$key.pub"
            CHMOD_COMMANDS+="chmod 644 .ssh/$key.pub; "
        fi
    done
else
    echo "Skipping SSH key setup."
fi
export CHMOD_COMMANDS # Export for podman exec


# --- Run setup commands as the user ---
echo "Configuring user environment in '$CONTAINER'..."
# We pass CHMOD_COMMANDS as an environment variable to be executed inside
podman exec -u "$USERNAME" -w "/home/$USERNAME" --env CHMOD_COMMANDS "$CONTAINER" /bin/zsh -c '
# --- Create standard directories first ---
mkdir -p .local/{share,state,bin} .config .ssh
chmod 700 .ssh

# --- Set SSH key permissions ---
eval $CHMOD_COMMANDS

# --- Install lazygit ---
if [ ! -f ".local/bin/lazygit" ]; then
    echo ">>> Installing Lazygit..."
    # Fixed quoting below:
    LG_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po "\"tag_name\": \"v\K[^\"]*")
    
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    mv lazygit .local/bin/
    rm lazygit.tar.gz
    echo "Lazygit installed to ~/.local/bin/lazygit"
fi

# --- Clone Neovim configuration ---
rm -rf .config/nvim
git clone https://github.com/andreluisos/nvim.git .config/nvim

# --- Download Tmux configuration ---
mkdir -p .config/tmux
curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
curl -fLo .config/tmux/status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
chmod +x .config/tmux/status.sh

if [ ! -d ".tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm .tmux/plugins/tpm
fi

# --- Force reinstallation of Oh My Zsh ---
if [ -d "$HOME/.oh-my-zsh" ]; then rm -rf "$HOME/.oh-my-zsh"; fi
if [ -f "$HOME/.zshrc" ]; then rm -f "$HOME/.zshrc"; fi
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# --- Install Zsh plugins ---
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM}/plugins"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM}/plugins/zsh-history-substring-search

# --- Configure .zshrc ---
sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" .zshrc
# Updated PATH command to include .local/bin and .cargo/bin
sed -i "s|# export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$PATH|export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$HOME/\.cargo/bin:\$PATH|g" .zshrc
grep -qxF "autoload -U compinit && compinit" .zshrc || echo "autoload -U compinit && compinit" >> .zshrc
grep -qF "keychain --eval" .zshrc || echo "\\n# Load SSH keys\\neval \$(keychain --eval --quiet \$(grep -srlF -e \"PRIVATE KEY\" ~/.ssh))" >> .zshrc

# --- Force reinstallation of SDKMAN! ---
if [ -d "$HOME/.sdkman" ]; then rm -rf "$HOME/.sdkman"; fi
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"

echo "Installing latest GraalVM CE..."
GRAALVM_IDENTIFIER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " ")
sdk install java $GRAALVM_IDENTIFIER

echo "Installing latest Gradle..."
sdk install gradle

# --- Install OpenCode ---
echo ">>> Installing OpenCode..."
curl -fsSL https://opencode.ai/install | bash

# --- Configure OpenCode with all LSPs disabled ---
echo ">>> Configuring OpenCode..."
mkdir -p .config/opencode
cat > .config/opencode/opencode.json << "OPENCODE_EOF"
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

# --- Install Rust ---
echo ">>> Installing Rust..."
rustup-init -y
'

echo "Dev environment setup complete for '$CONTAINER'!"
