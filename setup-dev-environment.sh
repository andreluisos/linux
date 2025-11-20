#!/bin/bash
set -e # Stop immediately if any command fails

# --- Define user variables ---
USERNAME="$USER"
UID_NUM=$(id -u)
GID_NUM=$(id -g)

# --- Get container name ---
read -p "Enter the name for the development container (e.g., 'fedora-dev'): " CONTAINER
if [[ -z "$CONTAINER" ]]; then echo "Aborting."; exit 1; fi
IMAGE_NAME="${CONTAINER}_image"

# --- Get Host Directory ---
DEFAULT_DIR="$HOME/Containers/$CONTAINER"
echo -e "\nWhere should the container's /home/$USERNAME be mapped on the host?"
read -p "Path (default: $DEFAULT_DIR): " INPUT_DIR
HOST_HOME_DIR="${INPUT_DIR:-$DEFAULT_DIR}"
HOST_HOME_DIR="${HOST_HOME_DIR/#\~/$HOME}"

if [ ! -d "$HOST_HOME_DIR" ]; then
    echo "Creating directory: $HOST_HOME_DIR"
    mkdir -p "$HOST_HOME_DIR"
fi

# --- Cleanup Old Container ---
if podman container exists "$CONTAINER"; then
    echo "Removing existing container '$CONTAINER'..."
    podman rm -f "$CONTAINER"
fi

# ==============================================================================
# PHASE 1: BUILD THE IMAGE
# ==============================================================================
echo "Phase 1: Building custom image with Systemd..."

# Create a temporary Containerfile
# We use printf for the service file to ensure newlines are handled correctly
cat <<EOF > Containerfile.tmp
FROM fedora:latest

# 1. Install Systemd and Base Tools
RUN dnf -y update && \
    dnf -y install systemd git zsh curl wget unzip fontconfig \
    util-linux-user procps-ng openssl-devel \
    neovim tmux fd-find fzf ripgrep \
    gcc gcc-c++ make cmake \
    glibc-langpack-en \
    iproute iputils \
    @development-tools rustup \
    && dnf clean all

# 2. Set Locale
ENV LANG=en_US.UTF-8

# 3. Set Timezone
RUN ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# 4. Create the Neovim Service Definition
RUN printf "[Unit]\n\
Description=Neovim Headless Server\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=$USERNAME\n\
ExecStart=/usr/bin/nvim --headless --listen 0.0.0.0:6000\n\
Restart=always\n\
RestartSec=3\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n" > /etc/systemd/system/nvim-headless.service

# Enable the service so it starts on boot
RUN systemctl enable nvim-headless.service

# 5. Create User
RUN groupadd -g $GID_NUM $USERNAME || true && \
    useradd -m -u $UID_NUM -g $GID_NUM -s /usr/bin/zsh $USERNAME && \
    echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME

# 6. Define Entrypoint
CMD ["/sbin/init"]
EOF

# Build the image (If this fails, the script stops here due to set -e)
podman build -t "$IMAGE_NAME" -f Containerfile.tmp .
rm Containerfile.tmp


# ==============================================================================
# PHASE 2: RUN THE CONTAINER
# ==============================================================================
echo "Phase 2: Starting the container..."

podman run -d --name "$CONTAINER" \
    --systemd=true \
    --userns=keep-id \
    --group-add keep-groups \
    -p 6000:6000 \
    -v "$HOST_HOME_DIR:/home/$USERNAME:Z" \
    "$IMAGE_NAME"

# Wait a moment for systemd to initialize
echo "Waiting for Systemd to initialize..."
sleep 5

if ! podman ps | grep -q "$CONTAINER"; then
    echo "ERROR: Container crashed. checking logs:"
    podman logs "$CONTAINER"
    exit 1
fi


# ==============================================================================
# PHASE 3: USER CONFIGURATION
# ==============================================================================
echo "Phase 3: Configuring user environment..."

# --- SSH Keys Injection ---
podman exec -u root "$CONTAINER" sh -c "mkdir -p /home/$USERNAME/.ssh && chown $USERNAME:$USERNAME /home/$USERNAME/.ssh"
HOST_SSH_DIR="$HOME/.ssh"
if [ -d "$HOST_SSH_DIR" ]; then
    echo "Found SSH keys on host. Copying..."
    find "$HOST_SSH_DIR" -maxdepth 1 -type f ! -name "known_hosts" ! -name "config" -exec podman cp {} "$CONTAINER:/home/$USERNAME/.ssh/" \;
    podman exec -u "$USERNAME" "$CONTAINER" chmod 700 .ssh
    podman exec -u "$USERNAME" "$CONTAINER" sh -c "chmod 600 .ssh/* 2>/dev/null || true"
    podman exec -u "$USERNAME" "$CONTAINER" sh -c "chmod 644 .ssh/*.pub 2>/dev/null || true"
fi

# --- Run User Setup Script ---
podman exec -u "$USERNAME" -w "/home/$USERNAME" "$CONTAINER" /bin/zsh -c '
# 1. Oh My Zsh
if [ ! -d ".oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# 2. Plugins
ZSH_CUSTOM=".oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM}/plugins"
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ] && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions

# 3. Zshrc
if [ -f .zshrc ]; then
    sed -i "s/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions)/g" .zshrc
    grep -q "cargo/bin" .zshrc || echo "export PATH=\$HOME/.cargo/bin:\$HOME/.local/bin:\$PATH" >> .zshrc
fi

# 4. Rust
if [ ! -d ".cargo" ]; then
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# 5. Java / SDKMAN
if [ ! -d ".sdkman" ]; then
    curl -s "https://get.sdkman.io" | bash
fi
source ".sdkman/bin/sdkman-init.sh"
if ! command -v java &> /dev/null; then
    sdk install java 21.0.2-graalce
    sdk install gradle
fi

# 6. Nerd Fonts
mkdir -p .local/share/fonts
if [ ! -d ".local/share/fonts/JetBrainsMonoNF" ]; then
    echo "Downloading Fonts..."
    curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
    unzip -o -q /tmp/fonts.zip -d .local/share/fonts/JetBrainsMonoNF
    rm /tmp/fonts.zip
    fc-cache -fv
fi

# 7. Nvim Config
if [ ! -d ".config/nvim" ]; then
    git clone https://github.com/andreluisos/nvim.git .config/nvim
fi

# 8. Tmux Config
mkdir -p .config/tmux
if [ ! -f ".config/tmux/tmux.conf" ]; then
    curl -fLo .config/tmux/tmux.conf https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
fi
if [ ! -f ".config/tmux/status.sh" ]; then
    curl -fLo .config/tmux/status.sh https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
    chmod +x .config/tmux/status.sh
fi
if [ ! -d ".tmux/plugins/tpm" ]; then git clone https://github.com/tmux-plugins/tpm .tmux/plugins/tpm; fi
'

echo "------------------------------------------------"
echo "Setup Complete!"
echo "1. Container: $CONTAINER"
echo "2. Host Dir:  $HOST_HOME_DIR"
echo "3. Neovim:    Listening on port 6000"
echo "------------------------------------------------"
