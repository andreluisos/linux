#!/bin/bash
# Need improvements.

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

rpm-ostree install gnome-boxes libvirt-daemon-config-network zsh

sudo usermod -aG libvirt $USER
sudo systemctle enable --now libvirtd virtnetworkd-ro.socket

sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)\nautoload -U compinit \&\& compinit/g' ~/.zshrc 
sed -i 's/# export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/g' ~/.zshrc
export PATH=$HOME/bin:/usr/local/bin:$PATH
zsh

flatpak install flathub org.freedesktop.Platform.ffmpeg-full -y
flatpak install flathub com.bitwarden.desktop -y
flatpak install flathub com.raggesilver.BlackBox -y
flatpak install flathub com.visualstudio.code -y
flatpak install flathub de.haeckerfelix.Fragments -y
flatpak install flathub fr.handbrake.ghb -y
flatpak install flathub org.mozilla.firefox -y

gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false
