#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -q
sudo apt-get install -y -q ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -q
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"

# Allow current user to run docker via sudo without a password
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/docker" | sudo tee /etc/sudoers.d/docker-"$USER" > /dev/null
sudo chmod 0440 /etc/sudoers.d/docker-"$USER"

echo ""
echo "Docker installed. 'sudo docker' works without a password prompt."
echo "Run 'newgrp docker' or log out/in to use docker without sudo."
docker --version
