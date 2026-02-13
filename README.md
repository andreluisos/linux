# Linux Development Environment

Automated setup for development environments on OSTree-based systems.

## Quick Start

### Option 1: Distrobox (Recommended for Isolated Environments)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/setup.sh)"
```

**Features:**
- Isolated home directories (containers have separate home folders)
- Manual SSH agent forwarding (secure)
- Neovim server with configurable port (default: 6000)
- GNOME keyboard shortcut for Neovide
- Full flexibility and customization

### Option 2: Toolbox (Recommended for Simplicity)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/toolbox-setup.sh)"
```

**Features:**
- Uses your regular home directory (shared with host)
- Automatic SSH agent forwarding (built-in, no setup needed)
- Neovim server with configurable port (default: 6000)
- GNOME keyboard shortcut for Neovide
- Official Red Hat project, well-integrated with Fedora/Silverblue

## Comparison: Distrobox vs Toolbox

| Feature | Distrobox (`setup.sh`) | Toolbox (`toolbox-setup.sh`) |
|---------|------------------------|------------------------------|
| **Home Directory** | Isolated per container | Shared with host |
| **SSH Agent** | Manual forwarding setup | Automatic (built-in) |
| **Flexibility** | High (custom images, options) | Opinionated, simpler |
| **Best For** | Isolated dev environments | Quick, simple setups |
| **Setup Complexity** | Moderate | Simple |

## Features

### SSH Agent Forwarding

**Distrobox:** SSH keys are never copied into the container. The host's SSH agent socket is mounted:
- Keys remain on the host only
- Works with hardware keys (YubiKey, etc.)
- No key synchronization issues
- Requires SSH agent running on host

**Toolbox:** SSH agent forwarding is automatic and built-in:
- Zero configuration needed
- Keys remain on the host only
- Works with hardware keys
- Just works out of the box

Test from inside either container:
```bash
ssh-add -l
```

### Configurable Neovim Server Port

During setup, you can specify which port the Neovim server should listen on (default: 6000).

## Choosing Between Distrobox and Toolbox

**Choose Distrobox if you:**
- Want isolated home directories for each container
- Need multiple independent development environments
- Want maximum flexibility and customization
- Don't mind slightly more complex setup

**Choose Toolbox if you:**
- Want to use your regular home directory
- Prefer official Red Hat tooling
- Want automatic SSH agent with zero config
- Prioritize simplicity over isolation

