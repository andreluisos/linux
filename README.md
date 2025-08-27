# Linux Development Environment Setup

A collection of scripts to automate the setup of a comprehensive Linux development environment, featuring GNOME desktop customization, containerized development with Podman, and the modern Ghostty terminal emulator.

## Quick Start

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/andreluisos/linux/refs/heads/main/setup.sh)"
```

## Features

### 🖥️ Desktop Environment
- **GNOME Configuration**: Optimized settings for development workflow
- **Font Installation**: JetBrains Mono Nerd Font with icon support
- **Keyboard Shortcuts**: Custom workspace navigation (Super+1-4)
- **UI Tweaks**: 24h clock, battery percentage, list view defaults

### 🐳 Containerized Development
- **Podman-based**: Isolated development environment using Fedora containers
- **Full Toolchain**: Pre-configured with Git, Zsh, Neovim, Tmux, and development tools
- **Java Development**: SDKMAN with GraalVM and Gradle
- **SSH Integration**: Keychain setup for seamless authentication

### 🖥️ Terminal Experience
- **Ghostty Terminal**: Modern, fast terminal emulator built from source
- **Tmux Configuration**: Enhanced terminal multiplexing with custom status bar
- **System Monitoring**: Real-time CPU, memory, temperature, and battery status
- **Oh My Zsh**: Feature-rich shell with plugins and autocompletion

## What Gets Installed

### System Configuration
- GNOME desktop settings optimization
- JetBrains Mono Nerd Font installation
- Custom environment variables and aliases

### Development Tools
- **Container**: Fedora-based development environment
- **Editors**: Neovim with custom configuration
- **Version Control**: Git with SSH key management
- **Build Tools**: Full development toolchain
- **Java Stack**: GraalVM, Gradle via SDKMAN

### Applications
- **Ghostty**: Modern terminal emulator (built from source)
- **Tmux**: Terminal multiplexer with custom configuration
- **Oh My Zsh**: Enhanced shell with plugins

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `setup.sh` | Main installation script with interactive prompts |
| `setup-dev-environment.sh` | Creates and configures Podman development container |
| `build-ghostty.sh` | Builds Ghostty terminal from source using containerized build |
| `create-ghostty-shortcut.sh` | Creates GNOME keyboard shortcut (Super+T) for Ghostty |

## Manual Installation

### 1. Clone Repository
```bash
git clone https://github.com/andreluisos/linux.git
cd linux
```

### 2. Run Individual Scripts
```bash
# Setup development environment
./setup-dev-environment.sh

# Build Ghostty terminal
./build-ghostty.sh

# Create desktop shortcut
./create-ghostty-shortcut.sh
```

## Configuration Files

- `ghostty` - Terminal emulator configuration
- `tmux` - Terminal multiplexer settings
- `tmux_status.sh` - Custom status bar script
- `silverblue` - Fedora Silverblue specific commands (work in progress)

## Requirements

- **OS**: Linux with GNOME desktop environment
- **Container Runtime**: Podman
- **Network**: Internet connection for downloads
- **Permissions**: Sudo access for system configuration

## Customization

The scripts are designed to be modular. You can:
- Skip specific components during interactive setup
- Modify configuration files before running scripts
- Run individual scripts as needed

## Fedora Silverblue Support

Partial support for Fedora Silverblue is included in the `silverblue` file, featuring:
- OSTree configuration
- Firewall optimization
- Swap file setup on Btrfs
- Package layering with rpm-ostree

## Contributing

Feel free to submit issues and enhancement requests. The project welcomes contributions that improve the development experience.
