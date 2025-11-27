#!/bin/bash

# --- Define user and host variables ---
USERNAME="$USER"

# --- Get container name from user ---
read -p "Enter the name for the development container (e.g., 'fedora-dev'): " CONTAINER
if [[ -z "$CONTAINER" ]]; then echo "Aborting."; exit 1; fi

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
    # Note: We don't auto-remove volumes here to prevent accidental data loss
fi

# --- Mode: CREATE or RECREATE ---
# This block runs for a new container or a recreated one
if [[ "$MODE" == "CREATE" || "$MODE" == "RECREATE" ]]; then
    
    # --- Storage Configuration ---
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
    if [[ -n "$ADDITIONAL_ARGS" ]]; then
        echo "Adding extra arguments: $ADDITIONAL_ARGS"
    fi

    podman run -d --name $CONTAINER \
      --network=host \
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
echo "Running setup as root in '$CONTAINER'..."
podman exec -u root "$CONTAINER" dnf update -y

# --- Install GitHub CLI (gh) ---
echo "Installing GitHub CLI..."
podman exec -u root "$CONTAINER" dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo -y
podman exec -u root "$CONTAINER" dnf install -y gh --repo gh-cli

# --- Install standard packages ---
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
# Ensure .ssh dir exists
podman exec -u root "$CONTAINER" sh -c "mkdir -p /home/$USERNAME/.ssh && chown $USERNAME:$USERNAME /home/$USERNAME/.ssh"

# Helper function to find keys
HOST_SSH_DIR="$HOME/.ssh"
CHMOD_COMMANDS=""

if [ -d "$HOST_SSH_DIR" ]; then
    # Find potential keys (id_rsa, id_ed25519, id_ecdsa)
    for key_type in id_rsa id_ed25519 id_ecdsa; do
        if [ -f "$HOST_SSH_DIR/$key_type" ]; then
            echo "Copying $key_type..."
            podman cp "$HOST_SSH_DIR/$key_type" "$CONTAINER:/home/$USERNAME/.ssh/$key_type"
            CHMOD_COMMANDS+="chmod 600 .ssh/$key_type; "
        fi
        if [ -f "$HOST_SSH_DIR/$key_type.pub" ]; then
            podman cp "$HOST_SSH_DIR/$key_type.pub" "$CONTAINER:/home/$USERNAME/.ssh/$key_type.pub"
            CHMOD_COMMANDS+="chmod 644 .ssh/$key_type.pub; "
        fi
    done
fi
export CHMOD_COMMANDS

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
# Updated PATH command
sed -i "s|# export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$PATH|export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$HOME/\.cargo/bin:\$PATH|g" .zshrc
grep -qxF "autoload -U compinit && compinit" .zshrc || echo "autoload -U compinit && compinit" >> .zshrc
# Add keychain loader (this fixes the SSH agent issue!)
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

# --- Configure OpenCode ---
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
