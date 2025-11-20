#!/bin/bash

# --- Define user variables ---
USERNAME="$USER"

# --- Get container name from user ---
read -p "Enter the name for the development container (e.g., 'fedora-dev'): " CONTAINER
if [[ -z "$CONTAINER" ]]; then
    echo "No name entered. Aborting setup."
    exit 1
fi

# --- Get Host Directory for Home ---
# We ask where the user wants to store the data on the host
DEFAULT_DIR="$HOME/Containers/$CONTAINER"
echo -e "\nWhere should the container's /home/$USERNAME be mapped on the host?"
read -p "Path (default: $DEFAULT_DIR): " INPUT_DIR

# Use default if empty, otherwise use input
HOST_HOME_DIR="${INPUT_DIR:-$DEFAULT_DIR}"

# Expand tilde (~) to $HOME just in case user typed it manually
HOST_HOME_DIR="${HOST_HOME_DIR/#\~/$HOME}"

# Create directory if it doesn't exist
if [ ! -d "$HOST_HOME_DIR" ]; then
    echo "Directory '$HOST_HOME_DIR' does not exist. Creating it..."
    mkdir -p "$HOST_HOME_DIR"
else
    echo "Using existing directory: $HOST_HOME_DIR"
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
    # Logic for if container doesn't exist
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
if [[ "$MODE" == "RECREATE" ]]; then
    echo "Removing container '$CONTAINER'..."
    podman rm -f "$CONTAINER"

    # NOTE: We do NOT delete the host directory here to preserve data.
    echo "Refusing to delete host directory '$HOST_HOME_DIR' automatically."
    echo "If you want a clean home, please manually empty that folder."
fi

# --- Mode: CREATE or RECREATE ---
if [[ "$MODE" == "CREATE" || "$MODE" == "RECREATE" ]]; then
    echo "Initializing container..."

    # --- Ask for additional container arguments ---
    read -p "Enter any additional arguments for 'podman run' (e.g., '-p 8080:8080'): " ADDITIONAL_ARGS
    if [[ -n "$ADDITIONAL_ARGS" ]]; then
        echo "Adding extra arguments: $ADDITIONAL_ARGS"
    fi

    # Run the new container
    # Note: Added ':Z' to the volume mount to handle SELinux permissions automatically
    podman run -d --name $CONTAINER \
      --userns=keep-id \
      --init \
      --group-add keep-groups \
      -v "$HOST_HOME_DIR:/home/$USERNAME:Z" \
      $ADDITIONAL_ARGS \
      fedora:latest \
      sleep infinity
fi

# --- Mode: CREATE, RECREATE, or UPDATE ---
# This block runs in all active modes to provision or update the container

# --- Run setup commands as root ---
echo "Running setup as root in '$CONTAINER'..."
podman exec -u root "$CONTAINER" dnf update -y
podman exec -u root "$CONTAINER" dnf install -y git zsh curl util-linux-user unzip fontconfig nvim tmux tzdata lm_sensors keychain fd fzf luarocks wget procps-ng openssl-devel @development-tools rustup

podman exec -u root "$CONTAINER" sh -c 'dnf install -y glibc-langpack-en && echo "LANG=en_US.UTF-8" > /etc/locale.conf'
podman exec -u root "$CONTAINER" ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Install JetBrains Mono Nerd Font
echo "Installing Nerd Fonts in '$CONTAINER'..."
podman exec -u root "$CONTAINER" sh -c '
curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
unzip -o /tmp/fonts.zip -d /usr/local/share/fonts/JetBrainsMonoNF
rm /tmp/fonts.zip
fc-cache -fv
'

# Configure user permissions 
podman exec -u root "$CONTAINER" sh -c "echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USERNAME"
podman exec -u root "$CONTAINER" sh -c "cp -n -rT /etc/skel/ /home/$USERNAME/ || true" 
podman exec -u root "$CONTAINER" usermod -d "/home/$USERNAME" -s /usr/bin/zsh "$USERNAME"


# --- SSH Key Injection ---
echo "Configuring SSH keys..."
# Ensure .ssh directory exists
podman exec -u root "$CONTAINER" sh -c "mkdir -p /home/$USERNAME/.ssh && chown $USERNAME:$USERNAME /home/$USERNAME/.ssh"

# Find private keys on the host
PRIVATE_KEYS=()
HOST_SSH_DIR="$HOME/.ssh"
if [ -d "$HOST_SSH_DIR" ]; then
    while IFS= read -r file_path; do
        PRIVATE_KEYS+=("$(basename "$file_path")")
    done < <(find "$HOST_SSH_DIR" -maxdepth 1 -type f ! -name "*.pub" ! -name "known_hosts" ! -name "config")
fi

SELECTED_KEYS=()
if [ ${#PRIVATE_KEYS[@]} -gt 0 ]; then
    echo "Found the following private SSH keys in $HOST_SSH_DIR:"
    for i in "${!PRIVATE_KEYS[@]}"; do
        echo "  $((i+1))) ${PRIVATE_KEYS[$i]}"
    done
    
    read -p "Which keys do you want to copy to the container? (e.g., '1 3', 'all', or 'none'): " -r REPLY_KEYS
    
    if [[ "$REPLY_KEYS" =~ ^[Aa][Ll][Ll]$ ]]; then
        SELECTED_KEYS=("${PRIVATE_KEYS[@]}")
    elif [[ "$REPLY_KEYS" != "none" && -n "$REPLY_KEYS" ]]; then
        for index in $REPLY_KEYS; do
            if [[ "$index" -gt 0 && "$index" -le ${#PRIVATE_KEYS[@]} ]]; then
                SELECTED_KEYS+=("${PRIVATE_KEYS[$((index-1))]}")
            fi
        done
    fi
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
podman exec -u "$USERNAME" -w "/home/$USERNAME" --env CHMOD_COMMANDS "$CONTAINER" /bin/zsh -c '
# --- Create standard directories first ---
mkdir -p .local/{share,state,bin} .config .ssh
chmod 700 .ssh

# --- Set SSH key permissions ---
if [ -n "$CHMOD_COMMANDS" ]; then
    eval $CHMOD_COMMANDS
fi

# --- Clone Neovim configuration ---
if [ ! -d ".config/nvim" ]; then
    git clone https://github.com/andreluisos/nvim.git .config/nvim
else
    echo "Neovim config already exists, skipping clone."
fi

# --- Download Tmux configuration ---
mkdir -p .config/tmux
if [ ! -f ".config/tmux/tmux.conf" ]; then
    curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
fi
if [ ! -f ".config/tmux/status.sh" ]; then
    curl -fLo .config/tmux/status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
    chmod +x .config/tmux/status.sh
fi

if [ ! -d ".tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm .tmux/plugins/tpm
fi

# --- Oh My Zsh ---
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- Install Zsh plugins ---
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM}/plugins"
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ] && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-history-substring-search" ] && git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM}/plugins/zsh-history-substring-search

# --- Configure .zshrc ---
if [ -f .zshrc ]; then
    sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" .zshrc
    sed -i "s|# export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$PATH|export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$HOME/\.cargo/bin:\$PATH|g" .zshrc
    grep -qxF "autoload -U compinit && compinit" .zshrc || echo "autoload -U compinit && compinit" >> .zshrc
    grep -qF "keychain --eval" .zshrc || echo "\\n# Load SSH keys\\neval \$(keychain --eval --quiet \$(grep -srlF -e \"PRIVATE KEY\" ~/.ssh))" >> .zshrc
fi

# --- SDKMAN! ---
if [ ! -d "$HOME/.sdkman" ]; then
    curl -s "https://get.sdkman.io" | bash
fi
source "$HOME/.sdkman/bin/sdkman-init.sh"

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo "Installing latest GraalVM CE..."
    GRAALVM_IDENTIFIER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " ")
    sdk install java $GRAALVM_IDENTIFIER
fi

if ! command -v gradle &> /dev/null; then
    echo "Installing latest Gradle..."
    sdk install gradle
fi

# --- Install Rust ---
if [ ! -d "$HOME/.cargo" ]; then
    echo "Installing Rust..."
    rustup-init -y
fi
'

echo "Dev environment setup complete for '$CONTAINER'!"
echo "Directory on host: $HOST_HOME_DIR"
