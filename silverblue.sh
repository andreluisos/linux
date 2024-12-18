#!/bin/bash
# Need improvements.

sudo ostree admin pin 0
sudo firewall-cmd --get-active-zone
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/tcp
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/udp
sudo firewall-cmd --reload
rpm-ostree install fish fzf gcc gnome-boxes gnome-shell-extension-pop-shell kitty libvirt-daemon-config-network neovim openssl-devel postgresql tmux
rpm-ostree override remove firefox firefox-langpacks

sudo usermod -aG libvirt $USER
sudo systemctl enable --now libvirtd virtnetworkd-ro.socket
flatpak install flathub -y org.gnome.TextEditor
flatpak install flathub -y org.mozilla.firefox
flatpak install flathub -y io.neovim.nvim
flatpak install flathub -y com.mattjakeman.ExtensionManager
flatpak install flathub -y com.jetbrains.WebStorm
flatpak install flathub -y com.jetbrains.RustRover
flatpak install flathub -y com.jetbrains.PyCharm-Professional
flatpak install flathub -y com.jetbrains.IntelliJ-IDEA-Ultimate
flatpak install flathub -y com.jetbrains.GoLand
flatpak install flathub -y com.jetbrains.CLion
flatpak install flathub -y com.google.Chrome
flatpak install flathub -y com.github.tchx84.Flatseal
flatpak install flathub -y org.freedesktop.Sdk.Extension.node22
flatpak install flathub -y org.freedesktop.Sdk.Extension.openjdk21
flatpak install flathub -y com.bitwarden.desktop
flatpak install flathub -y org.videolan.VLC

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
