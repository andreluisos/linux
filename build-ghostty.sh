#!/bin/bash

# This script uses Podman to create a temporary container to build the 'ghostty'
# and place the compiled binary in the local bin directory.

# Ensure the destination directory exists on the host
mkdir -p "$HOME/.local/bin"

# Run the temporary container
podman run \
  --rm \
  --name ghostty-builder \
  --user root \
  --userns=keep-id \
  -v "$HOME/.local/bin:/host-bin:Z" \
  registry.fedoraproject.org/fedora-toolbox:latest \
  sh -c "set -ex && \
          dnf install -y gtk4-devel gtk4-layer-shell-devel zig libadwaita-devel blueprint-compiler gettext git && \
          git clone https://github.com/ghostty-org/ghostty && \
          cd ghostty && \
          zig build -Doptimize=ReleaseFast && \
          mv zig-out/bin/ghostty /host-bin/"
