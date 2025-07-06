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

sudo btrfs subvolume create /var/swap
sudo chattr +C /var/swap
sudo chmod 600 /var/swap/swapfile
sudo mkswap /var/swap/swapfile
sudo swapon /var/swap/swapfile
echo '/var/swap/swapfile none swap defaults,pri=-2 0 0' | sudo tee -a /etc/fstab

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sudo dd if=/dev/zero of=/var/swap/swapfile bs=1M count=32768 status=progress
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)\nautoload -U compinit \&\& compinit/g' ~/.zshrc 
sed -i 's/# export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/g' ~/.zshrc
export PATH=$HOME/bin:/usr/local/bin:$PATH
zsh

git clone git@github.com:andreluisos/nvim.git ~/.config/nvim
