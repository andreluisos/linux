# Linux Development Environment

Automated setup for development environments using distrobox on OSTree-based systems.

## Quick Start

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/setup.sh)"
```

This sets up:

- Distrobox container with development tools
- SSH agent forwarding (secure key access without copying keys)
- Neovim server with configurable port (default: 6000)
- GNOME keyboard shortcut for Neovide
- JetBrains Mono Nerd Font

## Features

### SSH Agent Forwarding

SSH keys are never copied into the container. Instead, the host's SSH agent is forwarded securely:

- Keys remain on the host only
- Works with hardware keys (YubiKey, etc.)
- No key synchronization issues

**Requirements**: SSH agent must be running on the host with keys loaded.

Test from inside the container:
```bash
ssh-add -l
```

### Configurable Neovim Server Port

During setup, you can specify which port the Neovim server should listen on (default: 6000).
