#!/bin/bash
# Need improvements.

sudo ostree admin pin 0
sudo firewall-cmd --get-active-zone
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/tcp
sudo firewall-cmd --zone=FedoraWorkstation --permanent --remove-port=1025-65535/udp
sudo firewall-cmd --reload

rpm-ostree install gnome-boxes gnome-console langpacks-pt libvirt-daemon-config-network zsh
#### RESTART ####

rpm-ostree override remove firefox firefox-langpacks gnome-terminal-nautilus gnome-terminal
sudo usermod -aG libvirt $USER
sudo systemctl enable --now libvirtd virtnetworkd-ro.socket
#### RESTART ####

sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions zsh-history-substring-search)\nautoload -U compinit \&\& compinit/g' ~/.zshrc 
sed -i 's/# export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/export PATH=$HOME\/bin:\/usr\/local\/bin:$PATH/g' ~/.zshrc
export PATH=$HOME/bin:/usr/local/bin:$PATH
zsh

flatpak install flathub -y app.drey.Warp
flatpak install flathub -y com.bitwarden.desktop
flatpak install flathub -y com.github.tchx84.Flatseal
flatpak install flathub -y com.mattjakeman.ExtensionManager
flatpak install flathub -y com.visualstudio.code
flatpak install flathub -y fr.handbrake.ghb
flatpak install flathub -y io.missioncenter.MissionCenter
flatpak install flathub -y md.obsidian.Obsidian
flatpak install flathub -y net.cozic.joplin_desktop
flatpak install flathub -y org.fedoraproject.MediaWriter
flatpak install flathub -y org.freedesktop.Platform.ffmpeg-full
flatpak install flathub -y org.gaphor.Gaphor
flatpak install flathub -y org.gnome.Geary
flatpak install flathub -y org.gnome.Loupe
flatpak install flathub -y org.mozilla.firefox
flatpak install flathub -y org.videolan.VLC

gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false
