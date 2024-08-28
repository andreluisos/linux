#!/bin/bash

sudo firewall-cmd --get-active-zone
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/tcp
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/udp
sudo firewall-cmd --reload
sudo dnf install gnome-console zsh
sudo dnf remove gnome-tour gnome-terminal gnome-software gnome-weather rhythmbox libreoffice-core totem totem-pl-parser yelp baobab gnome-characters gnome-connections gnome-user-docs gnome-maps gnome-font-viewer evince loupe

sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"

# RUN ZSH'S install.sh BEFORE
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)\nautoload -U compinit \&\& compinit/g' ~/.zshrc 
sed -i 's/# export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/g' ~/.zshrc
export PATH=$HOME/bin:/usr/local/bin:$PATH

# ENABLE FLATHUB BEFORE
flatpak install com.bitwarden.desktop com.mattjakeman.ExtensionManager org.gnome.Papers org.gnome.Loupe org.videolan.VLC com.github.tchx84.Flatseal
