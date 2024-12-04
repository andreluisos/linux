#!/bin/bash

sudo firewall-cmd --get-active-zone
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/tcp
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/udp
sudo firewall-cmd --reload
sudo dnf install neovim fish
sudo dnf remove gnome-tour gnome-terminal gnome-software gnome-weather rhythmbox libreoffice-core totem totem-pl-parser yelp baobab gnome-characters gnome-connections gnome-user-docs gnome-maps gnome-font-viewer evince loupe

gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"

# ENABLE FLATHUB BEFORE
flatpak install com.bitwarden.desktop com.mattjakeman.ExtensionManager org.gnome.Papers org.gnome.Loupe org.videolan.VLC com.github.tchx84.Flatseal
