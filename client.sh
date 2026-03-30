#!/bin/bash
# Client Setup Script (Silverblue)

# 1. Directory & Permission Prep
mkdir -p ~/.ssh ~/.cloudflared ~/.config/systemd/user/
chmod 700 ~/.ssh

# 2. Cleanup Old Bridge (Conflict Prevention)
echo "🛑 Stopping old bridge if it exists..."
systemctl --user stop nvim-bridge 2>/dev/null || true
systemctl --user disable nvim-bridge 2>/dev/null || true

# 3. Intelligent SSH Config (Prevents Duplicates)
echo "📝 Configuring SSH..."
# We write to a temporary file then check if we should append
TEMP_CONF=$(mktemp)
cat <<EOF > "$TEMP_CONF"
Host dev.dataverdict.com.br
    # Running via Podman to keep the host clean
    ProxyCommand podman run --rm -i --user root -v $HOME/.cloudflared:/root/.cloudflared:Z docker.io/cloudflare/cloudflared:latest access ssh --hostname %h
EOF

if grep -q "Host dev.dataverdict.com.br" ~/.ssh/config 2>/dev/null; then
    echo "⚠️  Host dev.dataverdict.com.br already in config. Skipping append to avoid duplicates."
else
    cat "$TEMP_CONF" >> ~/.ssh/config
    echo "✅ Added host to ~/.ssh/config"
fi
rm "$TEMP_CONF"
chmod 600 ~/.ssh/config

# 4. Create the Systemd Tunnel Service
echo "⚙️  Creating systemd tunnel service..."
systemctl --user stop nvim-bridge.service
rm ~/.config/containers/systemd/nvim-bridge.container
cat <<EOF > ~/.config/containers/systemd/nvim-bridge.container
[Unit]
Description=Cloudflare Neovim Bridge (TCP)
After=network-online.target

[Container]
Image=docker.io/cloudflare/cloudflared:latest
# Mount your local cloudflared config to use your login token
Volume=%h/.cloudflared:/root/.cloudflared:Z
Exec=access tcp --hostname nvim.dataverdict.com.br --listener localhost:9999
Network=host

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF

# 5. Kickoff
systemctl --user daemon-reload
systemctl --user start nvim-bridge.service

echo "✨ Script finished!"
echo "👉 IMPORTANT: If this is a fresh setup, run this to log in first:"
echo "podman run --rm -it -v $HOME/.cloudflared:/root/.cloudflared:Z docker.io/cloudflare/cloudflared:latest access login dev.dataverdict.com.br"
echo "ssh developer@dev.dataverdict.com.br to enter"
echo "nvim --server localhost:9999"
