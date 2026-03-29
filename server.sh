#!/bin/bash
# Server Setup Script - DataVerdict Remote Environment
set -e

echo "🚀 Starting server-side environment setup..."

# 1. Ensure required directories exist
mkdir -p ~/.config/containers/systemd/
mkdir -p ~/.config/systemd/user/

# 2. Enable Linger (Allows user services to run without an active SSH session)
echo "🔧 Enabling linger for $USER..."
sudo loginctl enable-linger "$USER"

# 3. Handle Cloudflare Tunnel Secret
if ! podman secret inspect CLOUDFLARE_TUNNEL_TOKEN >/dev/null 2>&1; then
    read -sp "Enter your Cloudflare Tunnel Token: " CF_TOKEN
    echo
    echo "$CF_TOKEN" | podman secret create CLOUDFLARE_TUNNEL_TOKEN -
    echo "🔐 Secret 'CLOUDFLARE_TUNNEL_TOKEN' created."
else
    echo "✅ Secret 'CLOUDFLARE_TUNNEL_TOKEN' already exists. Skipping."
fi

# 4. Create the Cloudflared Gateway Quadlet
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

# 5. Create the Neovim Server Service
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

# 6. Apply changes and fire it up
echo "🔄 Reloading systemd and starting services..."
systemctl --user daemon-reload

# Start the tunnel and the nvim server
systemctl --user enable --now cloudflared-gateway
systemctl --user enable --now nvim-server

echo "✨ Setup complete!"
echo "Check tunnel status: journalctl --user -u cloudflared-gateway -f"
echo "Check nvim status:   systemctl --user status nvim-server"
