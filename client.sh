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
cat <<EOF > ~/.config/systemd/user/ssh-nvim-tunnel.service
[Unit]
Description=SSH Tunnel for Neovim (9999)
After=network-online.target

[Service]
# -N: No remote command
# # -T: Disable pseudo-terminal (less overhead)
# # -o TCPNoDelay=yes: The lag killer
ExecStart=/usr/bin/ssh -N -T -o "TCPNoDelay=yes" -o "ExitOnForwardFailure=yes" -L 9999:localhost:9999 developer@dev.dataverdict.com.br
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

# 5. Kickoff
systemctl --user daemon-reload
systemctl --user enable --now ssh-nvim-tunnel

echo "✨ Script finished!"
echo "👉 IMPORTANT: If this is a fresh setup, run this to log in first:"
echo "podman run --rm -it -v $HOME/.cloudflared:/root/.cloudflared:Z docker.io/cloudflare/cloudflared:latest access login dev.dataverdict.com.br"
echo "ssh developer@dev.dataverdict.com.br to enter"
echo "nvim --server localhost:9999"
