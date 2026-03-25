#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo bash scripts/install-docker-ubuntu.sh"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script supports Ubuntu/Debian systems with apt-get only."
  exit 1
fi

echo "Installing Docker prerequisites..."
apt-get update
apt-get install -y ca-certificates curl gnupg

echo "Adding Docker official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "Adding Docker apt repository..."
source /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

echo "Installing Docker Engine and plugins..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Enabling and starting Docker service..."
systemctl enable --now docker

echo
echo "Docker installation complete."
echo "Verify with: docker --version && docker run hello-world"
echo
echo "Optional: run Docker without sudo"
echo "  sudo usermod -aG docker \"$SUDO_USER\""
echo "  Then log out and back in."
