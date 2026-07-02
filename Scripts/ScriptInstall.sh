#!/bin/bash

echo "========================================================"
echo "ATUALIZANDO O SISTEMA"
echo "========================================================"

sudo apt update && sudo apt upgrade -y

echo "========================================================"
echo "INSTALAÇÃO DE PROGRAMAS ESSENCIAIS"
echo "========================================================"

sudo apt install git gparted vim gcc wget g++ htop vlc gimp openjdk-25-jdk libreoffice texlive-full texmaker -y 

echo "========================================================"
echo "INSTALAÇÃO GOOGLE CHROME"
echo "========================================================"

wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

sudo apt install ./google-chrome-stable_current_amd64.deb -y

sudo rm google-chrome-stable_current_amd64.deb

echo "========================================================"
echo "CONFIGURAÇÃO GITHUB (PARA NÃO PEDIR SENHA)"
echo "========================================================"

(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y

echo "========================================================"
