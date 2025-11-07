#!/bin/bash

# This script uses Podman to create a temporary container to build 'wezterm'
# and place the compiled binary in the local bin directory.

# Ensure the destination directory exists on the host
mkdir -p "$HOME/.local/bin"

# Run the temporary container
podman run \
  --rm \
  --name wezterm-builder \
  --user root \
  --userns=keep-id \
  -v "$HOME/.local/bin:/host-bin:Z" \
  registry.fedoraproject.org/fedora-toolbox:latest \
  sh -c "set -ex && \
         dnf install -y gcc-c++ rustc cargo clang-devel ncurses-devel libX11-devel libXcursor-devel libXfixes-devel libXinerama-devel libxkbcommon-devel libxkbcommon-x11-devel libXtst-devel openssl-devel desktop-file-utils wayland-devel wayland-protocols-devel mesa-libEGL-devel mesa-libGL-devel libxcb-devel xcb-util-devel xcb-util-image-devel fontconfig-devel xclip git && \
         git clone --depth=1 --branch=main --recursive https://github.com/wez/wezterm.git && \
         cd wezterm && \
         cargo build --release && \
         mv target/release/wezterm* /host-bin/"
