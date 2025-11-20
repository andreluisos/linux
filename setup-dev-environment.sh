#!/bin/bash
set -e # Stop on error

# --- Define user variables ---
USERNAME="$USER"
UID_NUM=$(id -u)
GID_NUM=$(id -g)

# --- Get container name ---
read -p "Enter the name for the development container (e.g., 'fedora-dev'): " CONTAINER
if [[ -z "$CONTAINER" ]]; then echo "Aborting."; exit 1; fi

IMAGE_NAME="${CONTAINER}_img"

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
# 1. WRITE THE ENTRYPOINT SCRIPT
# ============================================================
ENTRYPOINT_SCRIPT="$HOST_HOME_DIR/entrypoint.sh"

cat <<EOF > "$ENTRYPOINT_SCRIPT"
#!/bin/bash
set -e

# --- PATH CONFIGURATION ---
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$HOME/.sdkman/candidates/java/current/bin:\$HOME/.sdkman/candidates/gradle/current/bin:\$PATH"

# --- PROVISIONING FUNCTION ---
provision_user() {
    echo ">>> PROVISIONING: Checking environment..."
    
    mkdir -p \$HOME/.local/{share,state,bin} \$HOME/.config \$HOME/.ssh

    # 1. Oh My Zsh
    if [ ! -d "\$HOME/.oh-my-zsh" ]; then
        echo ">>> Installing Oh My Zsh..."
        # We check for zsh availability first to prevent loop crash
        if command -v zsh >/dev/null 2>&1; then
            sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        else
            echo "ERROR: Zsh binary missing. System install failed."
            exit 1
        fi
    fi

    # 2. Rust
    if [ ! -d "\$HOME/.cargo" ]; then
        echo ">>> Installing Rust..."
        curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi

    # 3. Java / SDKMAN
    if [ ! -d "\$HOME/.sdkman" ]; then
        echo ">>> Installing SDKMAN..."
        curl -s "https://get.sdkman.io" | bash
        source "\$HOME/.sdkman/bin/sdkman-init.sh"
        
        echo ">>> Installing Java..."
        if ! sdk install java 25-graalce; then
             # Fallback logic
             LATEST=\$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " ")
             sdk install java \$LATEST
        fi
        sdk install gradle
    fi

    # 4. Lazygit
    if [ ! -f "\$HOME/.local/bin/lazygit" ]; then
        echo ">>> Installing Lazygit..."
        LG_VER=\$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_\${LG_VER}_Linux_x86_64.tar.gz"
        tar xf lazygit.tar.gz lazygit
        mv lazygit \$HOME/.local/bin/
        rm lazygit.tar.gz
    fi

    # 5. Neovim Config
    if [ ! -d "\$HOME/.config/nvim" ]; then
        echo ">>> Cloning Neovim Config..."
        git clone https://github.com/andreluisos/nvim.git \$HOME/.config/nvim
        echo ">>> Bootstrapping Plugins..."
        /usr/bin/nvim --headless "+Lazy! sync" +qa
    fi

    # 6. Tmux
    mkdir -p \$HOME/.config/tmux
    if [ ! -f "\$HOME/.config/tmux/tmux.conf" ]; then
        curl -fLo \$HOME/.config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
        curl -fLo \$HOME/.config/tmux/status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
        chmod +x \$HOME/.config/tmux/status.sh
        git clone https://github.com/tmux-plugins/tpm \$HOME/.tmux/plugins/tpm
    fi

    # 7. Fix .zshrc for persistence
    if [ -f "\$HOME/.zshrc" ]; then
        sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions)/g" \$HOME/.zshrc
        if ! grep -q "export PATH=\$HOME/.local/bin" \$HOME/.zshrc; then
            echo "" >> \$HOME/.zshrc
            echo "# AUTO PATHS" >> \$HOME/.zshrc
            echo "export PATH=\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH" >> \$HOME/.zshrc
            echo "export SDKMAN_DIR=\"\$HOME/.sdkman\"" >> \$HOME/.zshrc
            echo "[[ -s \"\$HOME/.sdkman/bin/sdkman-init.sh\" ]] && source \"\$HOME/.sdkman/bin/sdkman-init.sh\"" >> \$HOME/.zshrc
        fi
    fi
}

provision_user

# --- SERVER LOOP ---
export SHELL=/usr/bin/zsh
PORT=6000

echo "Starting Neovim Server Loop..."
while true; do
   /usr/bin/nvim --headless --listen 0.0.0.0:\$PORT > /dev/null 2>&1
   sleep 1
done
EOF
chmod +x "$ENTRYPOINT_SCRIPT"

# ============================================================
# 2. CLEANUP OLD CONTAINERS/IMAGES
# ============================================================
if podman container exists "$CONTAINER"; then
    echo "Cleaning up old container..."
    podman rm -f "$CONTAINER"
fi
# We also remove the image to ensure we build a fresh one with latest packages
if podman image exists "$IMAGE_NAME"; then
    echo "Cleaning up old image..."
    podman rmi -f "$IMAGE_NAME"
fi

# ============================================================
# 3. PREPARE BASE SYSTEM (Root Phase)
# ============================================================
echo "Starting temporary install container..."
# Start a temporary fedora container to install RPMs
podman run -d --name "$CONTAINER" fedora:latest sleep infinity

echo "Installing System Packages (Root)..."
podman exec -u root "$CONTAINER" dnf update -y
# CRITICAL: We install zsh here so it exists in the image later
podman exec -u root "$CONTAINER" dnf install -y \
    git zsh curl util-linux-user unzip fontconfig \
    nvim tmux tzdata lm_sensors keychain fd fzf ripgrep \
    luarocks wget procps-ng lsof openssl-devel \
    gcc-c++ make cmake \
    @development-tools

echo "Configuring Locale & Time..."
podman exec -u root "$CONTAINER" sh -c 'dnf install -y glibc-langpack-en && echo "LANG=en_US.UTF-8" > /etc/locale.conf'
podman exec -u root "$CONTAINER" ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

echo "Creating User '$USERNAME'..."
podman exec -u root "$CONTAINER" sh -c "
    groupadd -g $GID_NUM $USERNAME || true
    useradd -m -u $UID_NUM -g $GID_NUM -s /usr/bin/zsh $USERNAME
    echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USERNAME
"

# ============================================================
# 4. COMMIT TO IMAGE (The Missing Link!)
# ============================================================
echo "Saving state to image '$IMAGE_NAME'..."
# This saves the Zsh installation into a reusable image
podman commit "$CONTAINER" "$IMAGE_NAME"

# Remove the temporary install container
podman rm -f "$CONTAINER"

# ============================================================
# 5. LAUNCH FINAL CONTAINER
# ============================================================
echo "Launching Final Container..."

podman run -d --name "$CONTAINER" \
    --restart=always \
    --userns=keep-id \
    --init \
    --group-add keep-groups \
    -p 6000:6000 \
    -v "$HOST_HOME_DIR:/home/$USERNAME:Z" \
    -u "$USERNAME" \
    -w "/home/$USERNAME" \
    "$IMAGE_NAME" \
    /bin/bash entrypoint.sh

echo "------------------------------------------------"
echo "Setup Complete!"
echo "Running logs (Ctrl+C to exit logs):"
echo "------------------------------------------------"
podman logs -f "$CONTAINER"
