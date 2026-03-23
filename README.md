# DevBox Setup - Complete Development Environment

Automated setup for a Fedora-based distrobox container with full development environment.

## Features

### Core Tools
- **Neovim** - Headless server running via systemd
- **Tmux** - With custom configuration and status bar
- **Git** - With SSH agent forwarding
- **Podman** - Socket forwarding from host (see "Podman Socket Forwarding" section)
- **Zsh** - Default shell
- **SDKMAN** - Java/JVM development
- **Rust** - Via rustup

### Podman Socket Forwarding
The host's Podman socket is forwarded to the container, enabling container workflows without running a separate daemon:

- **Uses host's Podman daemon** - No duplicate resource usage
- **Shares images with host** - No duplication of container images
- **Can build and run containers** - Full podman, buildah, skopeo support
- **Automatic setup** - Socket forwarding configured during container creation

**Enable on host:**
```bash
# Start the podman socket service
systemctl --user enable --now podman.socket

# Verify it's running
systemctl --user status podman.socket
```

**Example usage:**
```bash
# Enter the dev container
distrobox enter dev

# Check connection to host's podman
podman ps           # Lists containers running on host
podman images       # Shows host's images

# Pull an image (stored on host)
podman pull fedora:latest

# Run a container
podman run --rm -it fedora:latest bash

# Build an image
podman build -t myapp .

# Run with volume mounts
podman run --rm -v $(pwd):/work myapp
```

**Important notes:**
- Podman socket must be enabled on host first
- All images/containers are stored on the host
- Changes persist across container rebuilds
- Rootless mode on host (no sudo needed)

### Tmux Configuration
- 256-color support with RGB/truecolor
- Windows/panes start at index 1
- Mouse support enabled
- Custom status bar showing:
  - 🌡️ CPU temperature
  - 💻 CPU usage
  - 🧠 RAM usage
  - 💾 Swap usage
  - 🔋 Battery level
  - 📅 Date/time

### Tmux Plugins (via TPM)
- `tmux-sensible` - Sensible defaults
- `tmux-resurrect` - Save/restore sessions
- `tmux-continuum` - Auto-save every 15 minutes
- `vim-tmux-navigator` - Seamless vim/tmux navigation

### GNOME Keyboard Shortcuts
- **Super+T** - Launch Neovide GUI
- **Super+R** - Open terminal in container with tmux

## Files

```
distrobox/
├── setup.sh              # Main setup script (runs on host)
├── setup-env.sh         # System-level setup (runs as root in container)
├── setup-user-env.sh    # User-level setup (runs as user in container)
├── tmux.conf            # Tmux configuration
├── status.sh            # Status bar script
└── README.md            # This file
```

## Quick Start

### First Time Setup

1. Ensure SSH keys are loaded:
   ```bash
   ssh-add ~/.ssh/your_key
   ```

2. Run setup:
   ```bash
   cd ~/Documents/distrobox
   ./setup.sh
   ```

3. Setup will:
   - Remove existing 'dev' container
   - Create new container with isolated home
   - Install all packages and tools
   - Configure tmux, neovim, git, zsh
   - Start neovim headless server (systemd)
   - Create GNOME keyboard shortcuts

### Accessing the Container

**Via Keyboard Shortcut:**
- Press `Super+R` to open terminal with tmux
- Press `Super+T` to launch Neovide

**Via Command Line:**
```bash
distrobox enter dev
```

**Via Neovide (manual):**
```bash
neovide --server /tmp/nvimsocket
```

## Container Configuration

- **Name:** dev
- **Image:** fedora:latest
- **Home:** `~/Documents/containers/dev` (isolated)
- **Neovim Socket:** `/tmp/nvimsocket`
- **SSH Agent:** Forwarded from host automatically
- **Podman Socket:** Forwarded from host at `/run/user/1000/podman/podman.sock`

## Tmux Usage

### First Launch
The first time you run tmux, plugins will auto-install. If they don't:
```bash
# Inside tmux
Ctrl+B, I  # Install plugins
```

### Key Bindings (Default)
- `Ctrl+B` - Prefix key
- `Ctrl+B, %` - Split vertically
- `Ctrl+B, "` - Split horizontally
- `Ctrl+B, [` - Enter copy mode
- `Ctrl+B, d` - Detach session

### Vim-Tmux Navigation
- `Ctrl+H/J/K/L` - Navigate between vim splits and tmux panes

### Session Management
```bash
tmux new -s myproject     # Create named session
tmux attach -t myproject  # Attach to session
tmux ls                   # List sessions
tmux kill-session -t name # Kill session
```

Sessions are automatically saved every 15 minutes and restored on tmux startup.

## Neovim Server

The Neovim server runs automatically via systemd:

```bash
# Check status
systemctl --user status nvim-server.service

# Restart
systemctl --user restart nvim-server.service

# View logs
journalctl --user -u nvim-server.service -f
```

## SSH Agent Forwarding

SSH agent is automatically forwarded from host to container. No keys are stored in the container.

**Verify it's working:**
```bash
distrobox enter dev
ssh-add -l  # Should list your keys
```

## Customization

### Tmux Status Bar
Edit `~/.config/tmux/status.sh` inside the container to customize the status bar.

### Tmux Configuration
Edit `~/.config/tmux/tmux.conf` inside the container, then reload:
```bash
tmux source-file ~/.config/tmux/tmux.conf
```

### Neovim Configuration
Your nvim config is cloned from: `https://github.com/andreluisos/nvim.git`

To update:
```bash
cd ~/.config/nvim
git pull
```

## Rebuilding

To rebuild the container from scratch:
```bash
cd ~/Documents/distrobox
./setup.sh
```

This will:
- Destroy the old container
- Create a fresh container
- Run all setup scripts
- Preserve keyboard shortcuts (won't create duplicates)

## Troubleshooting

### Tmux plugins not loading
```bash
rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
# Then in tmux: Ctrl+B, I
```

### SSH agent not working
```bash
# On host
ssh-add -l  # Verify keys are loaded

# In container
echo $SSH_AUTH_SOCK  # Should show /run/user/1000/gcr/ssh
ssh-add -l           # Should list same keys as host
```

### Neovide won't connect
```bash
# Check if nvim server is running
systemctl --user status nvim-server.service

# Check socket exists
ls -la /tmp/nvimsocket

# Restart service
systemctl --user restart nvim-server.service
```

### Tmux status bar shows wrong info
The status bar reads from `/proc` - it shows container resource usage, not host resources. This is expected behavior in containers.

### Podman not working
```bash
# On host - check if socket is running
systemctl --user status podman.socket

# If not running, enable it
systemctl --user enable --now podman.socket

# In container - verify socket exists
ls -la /run/user/1000/podman/podman.sock

# In container - test connection
podman ps
podman images
```

## File Locations Inside Container

```
$HOME/
├── .config/
│   ├── nvim/              # Neovim configuration
│   └── tmux/
│       ├── tmux.conf      # Tmux config
│       └── status.sh      # Status bar script
├── .tmux/plugins/tpm/     # Tmux Plugin Manager
├── .sdkman/               # SDKMAN installation
├── .cargo/                # Rust installation
└── .zshrc                 # Zsh configuration
```

## Updates

### System Packages
```bash
distrobox enter dev
sudo dnf update -y
```

### Development Tools
```bash
# SDKMAN packages
sdk update
sdk upgrade

# Rust
rustup update

# Tmux plugins
# In tmux: Ctrl+B, U
```

---

**Last Updated:** March 23, 2026
**Container Image:** fedora:latest
**Distrobox Version:** Compatible with latest
