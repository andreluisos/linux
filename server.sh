  #!/bin/bash
# test.sh - Complete Development Server Setup (Bare Metal / DevBox)
# This script handles privilege escalation, system config, and user environment.
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

  if [ "$EUID" -eq 0 ] && [ -z "$USERNAME" ]; then
      USERNAME=$(getent passwd | awk -F: '$3 == 1000 {print $1; exit}')
  fi
  
  echo "==> Configuring system for user: $USERNAME"

  # 1. DNF Update (Allowed to fail if repos are locked)
  echo "==> Updating system packages..."
  dnf update -y || echo "Warning: DNF update had issues, continuing..."

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

  # 4. Passwordless Sudoers (Bare Metal Safe)
  if [ ! -f "/etc/sudoers.d/$USERNAME" ]; then
      echo "==> Configuring sudo permissions..."
      echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$USERNAME"
      chmod 0440 "/etc/sudoers.d/$USERNAME"
  fi

  # 5. Set Default Shell
  ZSH_PATH=$(which zsh)
  if [ -n "$ZSH_PATH" ]; then
      echo "==> Setting default shell to zsh..."
      chsh -s "$ZSH_PATH" "$USERNAME" 2>/dev/null || usermod -s "$ZSH_PATH" "$USERNAME" 2>/dev/null || true
  fi

  # 6. Enable linger
  loginctl enable-linger "$USER"

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

  # --- CRITICAL: FORCE HTTPS FOR GIT ---
  # This bypasses the 'Permission denied (publickey)' error on new servers
  git config --global url."https://github.com/".insteadOf "git@github.com:"

  # 1. Directories
  mkdir -p "$HOME/.local/bin" "$HOME/.config/tmux" "$HOME/.ssh" "$HOME/.local/share/fonts" "$HOME/.config/containers/systemd" "$HOME/.config/systemd/user"
  chmod 700 "$HOME/.ssh"

  # 2. JetBrains Mono Nerd Font
  FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNF"
  if [ ! -d "$FONT_DIR" ]; then
      echo "==> Installing JetBrains Mono Nerd Font..."
      curl -fLo /tmp/fonts.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/JetBrainsMono.zip
      unzip -oq /tmp/fonts.zip -d "$FONT_DIR"
      rm -f /tmp/fonts.zip
      fc-cache -f > /dev/null 2>&1
  fi

  # 3. Lazygit
  if [ ! -f "$HOME/.local/bin/lazygit" ]; then
      echo "==> Installing Lazygit..."
      LG_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -sLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
      tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
      mv /tmp/lazygit "$HOME/.local/bin/"
      rm -f /tmp/lazygit.tar.gz
  fi

  # 4. Neovim (HTTPS)
  echo "==> Setting up Neovim configuration..."
  rm -rf "$HOME/.config/nvim"
  git clone https://github.com/andreluisos/nvim.git "$HOME/.config/nvim"

  # 5. Tmux (Handle potential 404)
  echo "==> Setting up Tmux configuration..."
  # Try 'tmux' filename first, then 'tmux.conf'
  curl -sfLo "$HOME/.config/tmux/tmux.conf" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux || \
  curl -sfLo "$HOME/.config/tmux/tmux.conf" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/tmux.conf
  
  curl -sfLo "$HOME/.config/tmux/status.sh" https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/status.sh
  chmod +x "$HOME/.config/tmux/status.sh" 2>/dev/null || true

  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi

  # 7. Oh My Zsh (Force HTTPS & Non-interactive)
  echo "==> Installing Oh My Zsh..."
  rm -rf "$HOME/.oh-my-zsh" "$HOME/.zshrc"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

  # 8. Zsh Plugins (Explicit HTTPS)
  echo "==> Installing Zsh plugins..."
  ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
  mkdir -p "${ZSH_CUSTOM}/plugins"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" || true
  git clone https://github.com/zsh-users/zsh-autosuggestions.git "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" || true
  git clone https://github.com/zsh-users/zsh-completions.git "${ZSH_CUSTOM}/plugins/zsh-completions" || true
  git clone https://github.com/zsh-users/zsh-history-substring-search.git "${ZSH_CUSTOM}/plugins/zsh-history-substring-search" || true

  # 9. Configure .zshrc
  if [ -f "$HOME/.zshrc" ]; then
      echo "==> Configuring .zshrc..."
      sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)/g' "$HOME/.zshrc"
      echo 'export PATH=$HOME/.local/bin:$HOME/.cargo/bin:$PATH' >> "$HOME/.zshrc"
  fi

  # 10. Rust (Skip if exists)
  if [ ! -d "$HOME/.cargo" ]; then
      echo "==> Installing Rust..."
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  fi

  # 11. SDKMAN! & Java
  echo "==> Installing SDKMAN! & GraalVM..."
  rm -rf "$HOME/.sdkman"
  curl -s "https://get.sdkman.io" | bash
  
  # Source it within the script to use immediately
  export SDKMAN_DIR="$HOME/.sdkman"
  [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

  # Install Java & Gradle
  sdk install java 25.0.2-graalce || true
  sdk install gradle || true

  # Ensure SDKMAN init is in .zshrc
  if ! grep -q "sdkman-init.sh" "$HOME/.zshrc"; then
      cat >> "$HOME/.zshrc" << 'SDKMAN_EOF'
# SDKMAN initialization
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
SDKMAN_EOF
  fi

  # 12. OpenCode (AI Assistant)
  echo "==> Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash || echo "OpenCode install failed, skipping..."

  # 13. Handle Cloudflare Tunnel Secret
  if ! podman secret inspect CLOUDFLARE_TUNNEL_TOKEN >/dev/null 2>&1; then
      read -sp "Enter your Cloudflare Tunnel Token: " CF_TOKEN
      echo
      echo "$CF_TOKEN" | podman secret create CLOUDFLARE_TUNNEL_TOKEN -
      echo "🔐 Secret 'CLOUDFLARE_TUNNEL_TOKEN' created."
  else
      echo "✅ Secret 'CLOUDFLARE_TUNNEL_TOKEN' already exists. Skipping."
  fi

  # 14. Create the Cloudflared Gateway Quadlet
  # This single container handles both SSH (22) and Neovim (9999) traffic
  cat <<EOF > ~/.config/containers/systemd/cloudflared-gateway.container
[Unit]
Description=Cloudflare Tunnel Gateway
After=network-online.target

[Container]
Image=docker.io/cloudflare/cloudflared:latest
Secret=CLOUDFLARE_TUNNEL_TOKEN,type=env,target=TUNNEL_TOKEN
Exec=tunnel --no-autoupdate run
Network=host

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF

  # 15. Create the Neovim Server Service
  cat <<EOF > ~/.config/systemd/user/nvim-server.service
[Unit]
Description=Neovim Remote Server
After=network.target

[Service]
Type=simple
# Starts in your home directory by default
WorkingDirectory=%h
ExecStart=/usr/bin/nvim --headless --listen 127.0.0.1:9999
Restart=always

[Install]
WantedBy=default.target
EOF

  # 16. Apply changes and fire it up
  echo "🔄 Reloading systemd and starting services..."
  systemctl --user daemon-reload

  # Start the tunnel and the nvim server
  systemctl --user enable --now cloudflared-gateway
  systemctl --user enable --now nvim-server

  echo ""
  echo "=========================================="
  echo "✅ SETUP COMPLETE! RE-LOG TO APPLY SHELL"
  echo "=========================================="
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
if [ "$EUID" -eq 0 ]; then
  root_setup
  echo ""
  echo "==> Switching to user: $USERNAME"
  export -f user_setup
  su - "$USERNAME" -c "$(declare -f user_setup); user_setup"
else
  echo "Please run this script with: sudo bash $0"
  exit 1
fi

echo "All done! 🎉"
