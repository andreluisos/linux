#!/bin/bash
# setup.sh - Complete Development Container Setup
# This script automatically handles privilege escalation and runs both root and user setup
set -e

# Allow DNF update to fail without stopping the script
set +e
DNF_UPDATE_ALLOWED_TO_FAIL=true
set -e

# Detect username (works both as root and as user)
USERNAME="${SUDO_USER:-$USER}"

# ============================================================================
# ROOT SETUP FUNCTION
# ============================================================================
root_setup() {
    echo ""
    echo "=========================================="
    echo "PART 1: ROOT SETUP (System Configuration)"
    echo "=========================================="
    echo ""

    # Detect the primary user (UID 1000) - needed when running as actual root
    if [ "$EUID" -eq 0 ] && [ -z "$USERNAME" ]; then
        USERNAME=$(getent passwd | awk -F: '$3 == 1000 {print $1; exit}')
    fi
    
    echo "==> Configuring system for user: $USERNAME"

    # 1. DNF Update
    echo "==> Updating system packages..."
    dnf update -y || echo "Warning: DNF update had issues, continuing anyway..."

    # 2. Install GitHub CLI
    echo "==> Installing GitHub CLI..."
    if [ ! -f "/etc/yum.repos.d/gh-cli.repo" ]; then
        dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo -y
    fi
    dnf install -y gh --repo gh-cli 2>/dev/null || dnf install -y gh

    # 3. Install standard packages
    echo "==> Installing development packages..."
    dnf install -y git zsh curl util-linux-user unzip fontconfig nvim tmux tzdata \
      lm_sensors fd-find fzf luarocks wget procps-ng openssl-devel \
      @development-tools rustup

    # 4. Locale Configuration
    echo "==> Configuring locale..."
    dnf install -y glibc-langpack-en
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # 5. Timezone (Safe check)
    if [ ! -L "/etc/localtime" ] && [ ! -f "/etc/localtime" ]; then
        echo "==> Setting timezone..."
        ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
    else
        echo "==> Timezone managed by host. Skipping."
    fi

    # 6. Font installation note
    echo "==> Font installation will be done per-user..."

    # 7. Sudoers
    if [ ! -f "/etc/sudoers.d/$USERNAME" ]; then
        echo "==> Configuring sudo permissions..."
        echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$USERNAME"
        chmod 0440 "/etc/sudoers.d/$USERNAME"
    fi

    # 8. Initialize home directory from skeleton
    echo "==> Initializing home directory..."
    cp -rT /etc/skel/ "/home/$USERNAME/" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/"

    # 9. Change Default Shell to Zsh
    ZSH_PATH=$(which zsh)
    if [ -n "$ZSH_PATH" ]; then
        echo "==> Setting default shell to zsh..."
        # Use chsh instead of usermod for better compatibility
        chsh -s "$ZSH_PATH" "$USERNAME" 2>/dev/null || usermod -s "$ZSH_PATH" "$USERNAME" 2>/dev/null || true
    fi

    # 10. SSH Agent Forwarding - Configure environment
    echo "==> Configuring SSH agent forwarding..."
    mkdir -p "/home/$USERNAME/.ssh"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    chmod 700 "/home/$USERNAME/.ssh"
    
    # Note: SSH agent socket is mounted at /ssh-agent by the host setup script
    # We'll configure it in .zshrc later in the user setup phase

    echo "==> Root setup complete."
}

# ============================================================================
# USER SETUP FUNCTION
# ============================================================================
user_setup() {
    echo ""
    echo "=========================================="
    echo "PART 2: USER SETUP (Personal Configuration)"
    echo "=========================================="
    echo ""
    
    echo "==> Setting up user environment for: $(whoami)"

    # 1. Standard Directories
    echo "==> Creating standard directories..."
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.local/share/fonts" "$HOME/.config" "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # 2. Install JetBrains Mono Nerd Font
    FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNF"
    if [ ! -d "$FONT_DIR" ]; then
        echo "==> Installing JetBrains Mono Nerd Font..."
        mkdir -p /tmp/fonts
        curl -fLo /tmp/fonts/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
        mkdir -p "$FONT_DIR"
        unzip -q /tmp/fonts/fonts.zip -d "$FONT_DIR"
        rm -rf /tmp/fonts
        fc-cache -fv > /dev/null 2>&1
        echo "  - Font installed"
    else
        echo "==> JetBrains Mono Nerd Font already installed."
    fi

    # 3. SSH Key Permissions (if keys exist)
    echo "==> Setting SSH key permissions..."
    for key_type in id_rsa id_ed25519 id_ecdsa; do
        if [ -f "$HOME/.ssh/$key_type" ]; then
            chmod 600 "$HOME/.ssh/$key_type"
            echo "  - Set permissions for $key_type"
        fi
        if [ -f "$HOME/.ssh/${key_type}.pub" ]; then
            chmod 644 "$HOME/.ssh/${key_type}.pub"
        fi
    done

    # 4. Install Lazygit
    if [ ! -f "$HOME/.local/bin/lazygit" ]; then
        echo "==> Installing Lazygit..."
        LG_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
        tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
        mv /tmp/lazygit "$HOME/.local/bin/"
        rm /tmp/lazygit.tar.gz
        echo "  - Lazygit installed to ~/.local/bin/lazygit"
    else
        echo "==> Lazygit already installed."
    fi

    # 5. Clone Neovim Configuration
    echo "==> Setting up Neovim configuration..."
    rm -rf "$HOME/.config/nvim"
    git clone https://github.com/andreluisos/nvim.git "$HOME/.config/nvim"
    
    # Add zsh shell configuration to Neovim
    cat >> "$HOME/.config/nvim/lua/config/options.lua" << 'NVIM_SHELL_EOF'

-- Set shell to zsh explicitly
vim.o.shell = '/usr/bin/zsh'
vim.o.shellcmdflag = '-c'
NVIM_SHELL_EOF

    # 6. Tmux Configuration
    echo "==> Setting up Tmux configuration..."
    mkdir -p "$HOME/.config/tmux"
    curl -fLo "$HOME/.config/tmux/tmux.conf" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux
    curl -fLo "$HOME/.config/tmux/status.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
    chmod +x "$HOME/.config/tmux/status.sh"

    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        echo "==> Installing Tmux Plugin Manager..."
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    else
        echo "==> Tmux Plugin Manager already installed."
    fi

    # 7. Oh My Zsh - Force Reinstallation
    echo "==> Installing Oh My Zsh..."
    if [ -d "$HOME/.oh-my-zsh" ]; then
        rm -rf "$HOME/.oh-my-zsh"
    fi
    if [ -f "$HOME/.zshrc" ]; then
        rm -f "$HOME/.zshrc"
    fi
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    # 8. Zsh Plugins
    echo "==> Installing Zsh plugins..."
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    mkdir -p "${ZSH_CUSTOM}/plugins"

    [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] && \
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"

    [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] && \
        git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"

    [ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ] && \
        git clone https://github.com/zsh-users/zsh-completions "${ZSH_CUSTOM}/plugins/zsh-completions"

    [ ! -d "${ZSH_CUSTOM}/plugins/zsh-history-substring-search" ] && \
        git clone https://github.com/zsh-users/zsh-history-substring-search "${ZSH_CUSTOM}/plugins/zsh-history-substring-search"

    # 9. Configure .zshrc
    echo "==> Configuring .zshrc..."
    sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g' "$HOME/.zshrc"
    sed -i 's|# export PATH=\$HOME/bin:\$HOME/\.local/bin:/usr/local/bin:\$PATH|export PATH=\$HOME/bin:\$HOME/.local/bin:/usr/local/bin:\$HOME/.cargo/bin:\$PATH|g' "$HOME/.zshrc"

    # Add compinit if not present
    grep -qxF "autoload -U compinit && compinit" "$HOME/.zshrc" || echo "autoload -U compinit && compinit" >> "$HOME/.zshrc"

    # Configure SSH agent forwarding
    grep -qF "SSH_AUTH_SOCK" "$HOME/.zshrc" || cat >> "$HOME/.zshrc" << 'ZSHRC_EOF'

# SSH Agent Forwarding (from host)
if [ -S "/ssh-agent" ]; then
    export SSH_AUTH_SOCK="/ssh-agent"
fi
ZSHRC_EOF

    # 10. Install Rust
    if [ ! -d "$HOME/.cargo" ]; then
        echo "==> Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo "==> Rust already installed."
    fi

    # 11. SDKMAN! - Force Reinstallation
    echo "==> Installing SDKMAN!..."
    if [ -d "$HOME/.sdkman" ]; then
        rm -rf "$HOME/.sdkman"
    fi
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"

    # 12. Install GraalVM and Gradle via SDKMAN!
    echo "==> Installing GraalVM CE..."
    GRAALVM_IDENTIFIER=$(sdk list java | grep "graalce" | head -n 1 | cut -d"|" -f6 | tr -d " ")
    sdk install java "$GRAALVM_IDENTIFIER"

    echo "==> Installing Gradle..."
    sdk install gradle

    # 13. Install OpenCode
    echo "==> Installing OpenCode..."
    curl -fsSL https://opencode.ai/install | bash

    # 14. Configure OpenCode
    echo "==> Configuring OpenCode..."
    mkdir -p "$HOME/.config/opencode"
    cat > "$HOME/.config/opencode/opencode.json" << 'OPENCODE_EOF'
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

    # 15. Configure Neovim Service (TCP VERSION)
    echo "==> Configuring Neovim Systemd Service (TCP)..."
    sudo loginctl enable-linger $(whoami)
    mkdir -p "$HOME/.config/systemd/user"

    # Use NVIM_PORT environment variable, default to 6000
    NVIM_PORT="${NVIM_PORT:-6000}"

    cat > "$HOME/.config/systemd/user/nvim-server.service" <<SERVICE
[Unit]
Description=Neovim Headless (TCP)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/nvim --headless --listen 127.0.0.1:${NVIM_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
SERVICE

    systemctl --user daemon-reload
    systemctl --user enable --now nvim-server

    echo ""
    echo "=========================================="
    echo "✅ SETUP COMPLETE!"
    echo "=========================================="
    echo "Neovim server: 127.0.0.1:${NVIM_PORT}"
    echo "Connect with: neovide --server 127.0.0.1:${NVIM_PORT}"
    echo ""
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

if [ "$EUID" -eq 0 ]; then
    # Running as root - execute both parts
    echo "==> Detected root privileges"
    
    # Part 1: Root setup
    root_setup
    
    # Part 2: Switch to user and run user setup
    echo ""
    echo "==> Switching to user: $USERNAME"
    
    # Export functions and execute as user
    export -f user_setup
    su - "$USERNAME" -c "$(declare -f user_setup); user_setup"
    
else
    # Running as regular user - need to elevate
    echo "=========================================="
    echo "Development Container Setup"
    echo "=========================================="
    echo ""
    echo "This script needs root access for system configuration."
    echo ""
    
    # Check if we're in a distrobox/container environment
    if [ -f "/run/.containerenv" ] || [ -f "/.dockerenv" ]; then
        echo "==> Detected container environment"
        echo "==> Please run this script with: sudo bash $0"
        echo "==> Or in distrobox: distrobox enter devbox -- sudo bash /path/to/setup.sh"
        exit 1
    fi
    
    # Re-execute script with sudo
    exec sudo -E bash "$0" "$@"
fi

echo ""
echo "=========================================="
echo "All done! 🎉"
echo "=========================================="
