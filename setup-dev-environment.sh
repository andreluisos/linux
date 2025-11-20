#!/bin/bash

# --- Define user variables ---
USERNAME="$USER"

# --- Get container name ---
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

# ============================================================
# 1. CREATE THE ENTRYPOINT SCRIPT (On Host)
# ============================================================
# We write this to the host directory so it is persistent and mapped in.
ENTRYPOINT_SCRIPT="$HOST_HOME_DIR/entrypoint.sh"

cat <<EOF > "$ENTRYPOINT_SCRIPT"
#!/bin/bash

# Define the Neovim Loop Function
start_nvim_loop() {
    # 1. Wait for Nvim to be installed (for the very first run)
    while [ ! -x /usr/bin/nvim ]; do
        echo "Waiting for Neovim installation..."
        sleep 5
    done

    # 2. Set Zsh as the shell for Neovim's internal terminal
    export SHELL=/usr/bin/zsh
    
    # 3. The Infinite Loop
    while true; do
        echo "Starting Neovim Server..."
        # We run it headless. When client disconnects, it exits.
        /usr/bin/nvim --headless --listen 0.0.0.0:6000
        sleep 1
    done
}

# Start the loop in the background
start_nvim_loop &

# Keep the container alive forever (The replacement for sleep infinity)
exec sleep infinity
EOF

chmod +x "$ENTRYPOINT_SCRIPT"


# --- Container Creation Logic ---
MODE=""
if podman container exists "$CONTAINER"; then
    read -p "Container '$CONTAINER' exists. (R)ecreate, (U)pdate, or (S)kip? [U/r/s] " -r REPLY
    case "$REPLY" in
        [Rr]*) MODE="RECREATE" ;;
        [Ss]*) echo "Skipping."; exit 0 ;;
        *) MODE="UPDATE" ;;
    esac
else
    MODE="CREATE"
fi

# --- RECREATE ---
if [[ "$MODE" == "RECREATE" ]]; then
    echo "Removing container '$CONTAINER'..."
    podman rm -f "$CONTAINER"
fi

# --- CREATE/RECREATE ---
if [[ "$MODE" == "CREATE" || "$MODE" == "RECREATE" ]]; then
    echo "Initializing container..."
    read -p "Enter extra args (e.g. -p 6000:6000): " ADDITIONAL_ARGS
    
    # CRITICAL CHANGE:
    # We run the entrypoint.sh instead of sleep infinity directly.
    podman run -d --name $CONTAINER \
      --restart=always \
      --userns=keep-id \
      --init \
      --group-add keep-groups \
      -p 6000:6000 \
      -v "$HOST_HOME_DIR:/home/$USERNAME:Z" \
      $ADDITIONAL_ARGS \
      fedora:latest \
      /bin/bash "/home/$USERNAME/entrypoint.sh"
fi

# --- INSTALLATION ---
echo "Running setup as root..."
podman exec -u root "$CONTAINER" dnf update -y
podman exec -u root "$CONTAINER" dnf install -y \
    git zsh curl util-linux-user unzip fontconfig \
    nvim tmux tzdata lm_sensors keychain fd fzf \
    luarocks wget procps-ng lsof openssl-devel \
    @development-tools rustup

# Locale & Time
podman exec -u root "$CONTAINER" sh -c 'dnf install -y glibc-langpack-en && echo "LANG=en_US.UTF-8" > /etc/locale.conf'
podman exec -u root "$CONTAINER" ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Nerd Fonts
echo "Installing Nerd Fonts..."
podman exec -u root "$CONTAINER" sh -c '
curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
mkdir -p /usr/local/share/fonts/JetBrainsMonoNF
unzip -o -q /tmp/fonts.zip -d /usr/local/share/fonts/JetBrainsMonoNF
rm /tmp/fonts.zip
fc-cache -fv
'

# Permissions & Force Shell
podman exec -u root "$CONTAINER" sh -c "echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USERNAME"
podman exec -u root "$CONTAINER" sh -c "cp -n -rT /etc/skel/ /home/$USERNAME/ || true" 
podman exec -u root "$CONTAINER" usermod -d "/home/$USERNAME" -s /usr/bin/zsh "$USERNAME"

# SSH Keys
echo "Configuring SSH keys..."
podman exec -u root "$CONTAINER" sh -c "mkdir -p /home/$USERNAME/.ssh && chown $USERNAME:$USERNAME /home/$USERNAME/.ssh"
HOST_SSH_DIR="$HOME/.ssh"
if [ -d "$HOST_SSH_DIR" ]; then
    find "$HOST_SSH_DIR" -maxdepth 1 -type f ! -name "known_hosts" ! -name "config" -exec podman cp {} "$CONTAINER:/home/$USERNAME/.ssh/" \; 2>/dev/null || true
    podman exec -u "$USERNAME" "$CONTAINER" chmod 700 .ssh
    podman exec -u "$USERNAME" "$CONTAINER" sh -c "chmod 600 .ssh/* 2>/dev/null || true"
    podman exec -u "$USERNAME" "$CONTAINER" sh -c "chmod 644 .ssh/*.pub 2>/dev/null || true"
fi


# --- USER CONFIGURATION ---
echo "Configuring user environment..."
podman exec -u "$USERNAME" -w "/home/$USERNAME" "$CONTAINER" /bin/zsh -c '
mkdir -p .local/{share,state,bin} .config .ssh

# 1. Oh My Zsh & Plugins
if [ ! -d ".oh-my-zsh" ]; then sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; fi
ZSH_CUSTOM=".oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM}/plugins"
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ] && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-history-substring-search" ] && git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM}/plugins/zsh-history-substring-search

# 2. Zshrc Config
if [ -f .zshrc ]; then
    sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g" .zshrc
    sed -i "s|# export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$PATH|export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$HOME/\.cargo/bin:\$PATH|g" .zshrc
    grep -qxF "autoload -U compinit && compinit" .zshrc || echo "autoload -U compinit && compinit" >> .zshrc
    grep -qF "keychain --eval" .zshrc || echo "\\n# Load SSH keys\\neval \$(keychain --eval --quiet \$(grep -srlF -e \"PRIVATE KEY\" ~/.ssh))" >> .zshrc
fi

# 3. Tools
if [ ! -d ".sdkman" ]; then curl -s "https://get.sdkman.io" | bash; fi
source ".sdkman/bin/sdkman-init.sh"
if ! command -v java &> /dev/null; then sdk install java 21.0.2-graalce; sdk install gradle; fi
if [ ! -d ".cargo" ]; then curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; fi

# 4. Tmux
mkdir -p .config/tmux
[ ! -f ".config/tmux/tmux.conf" ] && curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
[ ! -f ".config/tmux/status.sh" ] && curl -fLo .config/tmux/status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh && chmod +x .config/tmux/status.sh
if [ ! -d ".tmux/plugins/tpm" ]; then git clone https://github.com/tmux-plugins/tpm .tmux/plugins/tpm; fi

# 5. NVIM Config & Bootstrap
if [ ! -d ".config/nvim" ]; then 
    git clone https://github.com/andreluisos/nvim.git .config/nvim
    echo "Bootstrapping Neovim plugins..."
    /usr/bin/nvim --headless "+Lazy! sync" +qa
fi
'

echo "------------------------------------------------"
echo "Setup Complete!"
echo "Restarting container to pick up all changes..."
podman restart "$CONTAINER"
echo "------------------------------------------------"
echo "1. Neovim Server is running on port 6000."
echo "2. It starts automatically when the container starts."
echo "3. No Host Dependencies. No Systemd."
echo "------------------------------------------------"
