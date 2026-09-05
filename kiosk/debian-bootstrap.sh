#!/bin/sh
CODENAME=$(grep VERSION_CODENAME= /etc/os-release | cut -d= -f2)
echo deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware > /etc/apt/sources.list
echo deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware >> /etc/apt/sources.list
echo deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware >> /etc/apt/sources.list
apt-get update
apt-get install -y sudo openssh-server isc-dhcp-client network-manager wpasupplicant firmware-realtek firmware-misc-nonfree git
usermod -aG sudo arcadebox
systemctl enable --now ssh
ip -4 -br addr
