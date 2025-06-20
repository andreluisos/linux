#!/bin/bash
# Need improvements.

gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false

sudo ostree admin pin 0
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/tcp --remove-port=1025-65535/udp
sudo firewall-cmd --reload
rpm-ostree install distrobox gnome-boxes libvirt-daemon-config-network postgresql zsh
# Reboot
sudo usermod -aG libvirt $USER
sudo systemctl enable --now libvirtd virtnetworkd-ro.socket
