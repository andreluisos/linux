#!/bin/bash

# --- Define user and host variables ---
USERNAME="$USER"
HOST_XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
HOST_WAYLAND_DISPLAY=$WAYLAND_DISPLAY
CONTAINER_XDG_RUNTIME_DIR="/run/user/$(id -u)"

# --- Get container name from user ---
read -p "Enter the name for the development container (e.g., 'fedora-dev'): " CONTAINER
if [[ -z "$CONTAINER" ]]; then
    echo "No name entered. Aborting setup."
    exit 1
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
            echo "Removing volume '$CONTAINER' for a clean slate..."
            podman volume rm -f "$CONTAINER"
        else
            echo "Keeping the existing volume '$CONTAINER'."
        fi
    fi
fi

# --- Mode: CREATE or RECREATE ---
# This block runs for a new container or a recreated one
if [[ "$MODE" == "CREATE" || "$MODE" == "RECREATE" ]]; then
    echo "Creating new volume and container..."

    # Create the volume only if it doesn't exist
    if ! podman volume exists "$CONTAINER"; then
        podman volume create "$CONTAINER"
    fi

    # Run the new container
    podman run -d --name $CONTAINER \
      --userns=keep-id \
      --group-add keep-groups \
      --security-opt label=disable \
      -v $CONTAINER:/home/$USERNAME \
      -e WAYLAND_DISPLAY=$HOST_WAYLAND_DISPLAY \
      -e XDG_RUNTIME_DIR=$CONTAINER_XDG_RUNTIME_DIR \
      -v $HOST_XDG_RUNTIME_DIR:$CONTAINER_XDG_RUNTIME_DIR \
      fedora:latest \
      sleep infinity
fi

# --- Mode: CREATE, RECREATE, or UPDATE ---
# This block runs in all active modes to provision or update the container

# --- Run setup commands as root ---
echo "Running setup as root in '$CONTAINER'..."
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


# --- SSH Key Injection ---
echo "Configuring SSH keys..."
# Ensure .ssh directory exists and has correct root ownership for the user
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
# We pass CHMOD_COMMANDS as an environment variable to be executed inside
podman exec -u "$USERNAME" -w "/home/$USERNAME" --env CHMOD_COMMANDS "$CONTAINER" /bin/zsh -c '
# --- Create standard directories first ---
mkdir -p .local/{share,state,bin} .config .ssh
chmod 700 .ssh

# --- Set SSH key permissions ---
eval $CHMOD_COMMANDS

# --- Clone Neovim configuration ---
rm -rf .config/nvim
git clone https://github.com/andreluisos/nvim.git .config/nvim

# --- Download Tmux configuration ---
mkdir -p .config/tmux
curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
curl -fLo .config/tmux/tmux_status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux_status.sh
chmod +x .config/tmux/tmux_status.sh

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

# --- Install Rust ---
echo "Installing Rust..."
rustup-init -y
'

echo "Dev environment setup complete for '$CONTAINER'!"
