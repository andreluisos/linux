#!/bin/bash

# --- Define user variables ---
USERNAME="$USER"

# --- Get container name ---
read -p "Enter the name for the development container (e.g., 'fedora-dev'): " CONTAINER
if [[ -z "$CONTAINER" ]]; then echo "No name entered. Aborting."; exit 1; fi

# --- Get Host Directory ---
DEFAULT_DIR="$HOME/Containers/$CONTAINER"
echo -e "\nWhere should the container's /home/$USERNAME be mapped on the host?"
read -p "Path (default: $DEFAULT_DIR): " INPUT_DIR
HOST_HOME_DIR="${INPUT_DIR:-$DEFAULT_DIR}"
# Fix tilde expansion if user typed explicit '~'
HOST_HOME_DIR="${HOST_HOME_DIR/#\~/$HOME}"

if [ ! -d "$HOST_HOME_DIR" ]; then
    echo "Directory '$HOST_HOME_DIR' does not exist. Creating it..."
    mkdir -p "$HOST_HOME_DIR"
fi

# --- Cleanup Old Container (Force Recreate logic for this fix) ---
if podman container exists "$CONTAINER"; then
    echo "Removing existing container '$CONTAINER' to fix the startup configuration..."
    podman rm -f "$CONTAINER"
fi

echo "Phase 1: Initializing container for installation..."

# --- PHASE 1: START WITH SLEEP (To allow installation) ---
# We do NOT use systemd yet. We just want it running to install packages.
podman run -d --name $CONTAINER \
  --userns=keep-id \
  --group-add keep-groups \
  -p 6000:6000 \
  -v "$HOST_HOME_DIR:/home/$USERNAME:Z" \
  fedora:latest \
  sleep infinity

# --- INSTALLATION ---
echo "Installing system packages (including Systemd)..."
podman exec -u root "$CONTAINER" dnf update -y
# Added 'systemd' explicitly to the install list so /sbin/init exists later
podman exec -u root "$CONTAINER" dnf install -y systemd git zsh curl util-linux-user unzip fontconfig nvim tmux tzdata lm_sensors keychain fd fzf luarocks wget procps-ng openssl-devel @development-tools rustup

# Locale & Time
podman exec -u root "$CONTAINER" sh -c 'dnf install -y glibc-langpack-en && echo "LANG=en_US.UTF-8" > /etc/locale.conf'
podman exec -u root "$CONTAINER" ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Nerd Fonts
echo "Installing Nerd Fonts..."
podman exec -u root "$CONTAINER" sh -c '
curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
unzip -o /tmp/fonts.zip -d /usr/local/share/fonts/JetBrainsMonoNF
rm /tmp/fonts.zip
fc-cache -fv
'

# User Config
podman exec -u root "$CONTAINER" sh -c "echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USERNAME"
podman exec -u root "$CONTAINER" sh -c "cp -n -rT /etc/skel/ /home/$USERNAME/ || true" 
podman exec -u root "$CONTAINER" usermod -d "/home/$USERNAME" -s /usr/bin/zsh "$USERNAME"

# SSH Keys
echo "Configuring SSH keys..."
podman exec -u root "$CONTAINER" sh -c "mkdir -p /home/$USERNAME/.ssh && chown $USERNAME:$USERNAME /home/$USERNAME/.ssh"
PRIVATE_KEYS=()
HOST_SSH_DIR="$HOME/.ssh"
if [ -d "$HOST_SSH_DIR" ]; then
    while IFS= read -r file_path; do PRIVATE_KEYS+=("$(basename "$file_path")"); done < <(find "$HOST_SSH_DIR" -maxdepth 1 -type f ! -name "*.pub" ! -name "known_hosts" ! -name "config")
fi
SELECTED_KEYS=()
if [ ${#PRIVATE_KEYS[@]} -gt 0 ]; then
    echo "Found SSH keys:"
    for i in "${!PRIVATE_KEYS[@]}"; do echo "  $((i+1))) ${PRIVATE_KEYS[$i]}"; done
    read -p "Which keys to copy? (e.g., '1 3', 'all', 'none'): " -r REPLY_KEYS
    if [[ "$REPLY_KEYS" =~ ^[Aa][Ll][Ll]$ ]]; then SELECTED_KEYS=("${PRIVATE_KEYS[@]}")
    elif [[ "$REPLY_KEYS" != "none" && -n "$REPLY_KEYS" ]]; then
        for index in $REPLY_KEYS; do
            if [[ "$index" -gt 0 && "$index" -le ${#PRIVATE_KEYS[@]} ]]; then SELECTED_KEYS+=("${PRIVATE_KEYS[$((index-1))]}") ; fi
        done
    fi
fi
CHMOD_COMMANDS=""
if [ ${#SELECTED_KEYS[@]} -gt 0 ]; then
    for key in "${SELECTED_KEYS[@]}"; do
        if [ -f "$HOST_SSH_DIR/$key" ]; then
            podman cp "$HOST_SSH_DIR/$key" "$CONTAINER:/home/$USERNAME/.ssh/$key"
            CHMOD_COMMANDS+="chmod 600 .ssh/$key; "
        fi
        if [ -f "$HOST_SSH_DIR/$key.pub" ]; then
            podman cp "$HOST_SSH_DIR/$key.pub" "$CONTAINER:/home/$USERNAME/.ssh/$key.pub"
            CHMOD_COMMANDS+="chmod 644 .ssh/$key.pub; "
        fi
    done
fi
export CHMOD_COMMANDS

# User Environment Setup
echo "Configuring user environment..."
podman exec -u "$USERNAME" -w "/home/$USERNAME" --env CHMOD_COMMANDS "$CONTAINER" /bin/zsh -c '
mkdir -p .local/{share,state,bin} .config .ssh
chmod 700 .ssh
if [ -n "$CHMOD_COMMANDS" ]; then eval $CHMOD_COMMANDS; fi
if [ ! -d ".config/nvim" ]; then git clone https://github.com/andreluisos/nvim.git .config/nvim; fi
mkdir -p .config/tmux
[ ! -f ".config/tmux/tmux.conf" ] && curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
[ ! -f ".config/tmux/status.sh" ] && curl -fLo .config/tmux/status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh && chmod +x .config/tmux/status.sh
[ ! -d ".tmux/plugins/tpm" ]; then git clone https://github.com/tmux-plugins/tpm .tmux/plugins/tpm; fi
if [ ! -d "$HOME/.oh-my-zsh" ]; then sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; fi
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM}/plugins"
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ] && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-history-substring-search" ] && git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM}/plugins/zsh-history-substring-search
if [ -f .zshrc ]; then
    sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" .zshrc
    sed -i "s|# export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$PATH|export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$HOME/\.cargo/bin:\$PATH|g" .zshrc
    grep -qxF "autoload -U compinit && compinit" .zshrc || echo "autoload -U compinit && compinit" >> .zshrc
    grep -qF "keychain --eval" .zshrc || echo "\\n# Load SSH keys\\neval \$(keychain --eval --quiet \$(grep -srlF -e \"PRIVATE KEY\" ~/.ssh))" >> .zshrc
fi
if [ ! -d "$HOME/.sdkman" ]; then curl -s "https://get.sdkman.io" | bash; fi
source "$HOME/.sdkman/bin/sdkman-init.sh"
if ! command -v java &> /dev/null; then
    GRAALVM_IDENTIFIER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " ")
    sdk install java $GRAALVM_IDENTIFIER
fi
if ! command -v gradle &> /dev/null; then sdk install gradle; fi
if [ ! -d "$HOME/.cargo" ]; then rustup-init -y; fi
'

# --- SETUP NEOVIM SERVICE (File creation only) ---
echo "Pre-creating Neovim service definition..."
podman exec -u root "$CONTAINER" sh -c "cat <<EOF > /etc/systemd/system/nvim-headless.service
[Unit]
Description=Neovim Headless Server
After=network.target

[Service]
Type=simple
User=$USERNAME
ExecStart=/usr/bin/nvim --headless --listen 0.0.0.0:6000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF"

# --- PHASE 2: COMMIT AND RESTART WITH SYSTEMD ---
echo "Phase 2: Switching to Systemd mode..."

# 1. Commit the current state (with systemd installed) to a new image
IMAGE_NAME="${CONTAINER}_image"
echo "Committing installed state to image '$IMAGE_NAME'..."
podman commit "$CONTAINER" "$IMAGE_NAME"

# 2. Remove the temporary setup container
podman rm -f "$CONTAINER"

# 3. Run the FINAL container using the new image and /sbin/init
echo "Starting final container with Systemd..."
podman run -d --name $CONTAINER \
  --userns=keep-id \
  --systemd=true \
  --group-add keep-groups \
  -p 6000:6000 \
  -v "$HOST_HOME_DIR:/home/$USERNAME:Z" \
  "$IMAGE_NAME" \
  /sbin/init

# 4. Enable the service
echo "Enabling Neovim service..."
podman exec -u root "$CONTAINER" systemctl enable --now nvim-headless.service

echo "----------------------------------------------------"
echo "Success! Container '$CONTAINER' is running."
echo "1. Neovim is listening on port 6000."
echo "2. Systemd is active."
echo "----------------------------------------------------"
