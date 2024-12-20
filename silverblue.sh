#!/bin/bash
# Need improvements.

sudo ostree admin pin 0
sudo firewall-cmd --zone=$(sudo firewall-cmd --get-active-zone | head -n 1 | awk '{print $1}'
) --permanent --remove-port=1025-65535/tcp --remove-port=1025-65535/udp --reload
sudo firewall-cmd --reload
rpm-ostree install fish gnome-boxes kitty libvirt-daemon-config-network neovim tmux
rpm-ostree override remove firefox firefox-langpacks

sudo usermod -aG libvirt $USER
sudo systemctl enable --now libvirtd virtnetworkd-ro.socket

flatpak install flathub -y org.mozilla.firefox \
com.mattjakeman.ExtensionManager \
com.jetbrains.WebStorm \
com.jetbrains.RustRover \
com.jetbrains.PyCharm-Professional \
com.jetbrains.IntelliJ-IDEA-Ultimate \
com.jetbrains.GoLand \
com.jetbrains.CLion \
com.github.tchx84.Flatseal \
com.bitwarden.desktop \
org.videolan.VLC


gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false

flatpak override --user --env=PATH="/app/bin:/usr/bin:$HOME/.asdf/shims" io.neovim.nvim
flatpak override --user --filesystem="$HOME/.asdf/shims/fd:ro" io.neovim.nvim
flatpak override --user --filesystem="$HOME/.asdf/shims/lazygit:ro" io.neovim.nvim
flatpak override --user --env=FLATPAK_ENABLE_SDK_EXT=node22,openjdk21 io.neovim.nvim
flatpak override --user --socket=ssh-auth io.neovim.nvim
