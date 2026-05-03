#!/bin/bash

echo "ATUALIZANDO SISTEMA..."
sudo apt update && sudo apt upgrade -y

echo "INSTALANDO PROGRAMAS ESSENCIAIS"
sudo apt install -y vlc libreoffice gimp

echo "INSTALANDO GOOGLE CHROME..."
# Baixa como usuário normal direto da internet
# O -y nos comandos significa que é para aceitar direto
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

# Instala com sudo
sudo apt install -y ./google-chrome-stable_current_amd64.deb

# Remove arquivo baixado depois
rm -f google-chrome-stable_current_amd64.deb


