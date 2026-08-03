#!/usr/bin/env bash
set -euo pipefail

# Usage check
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

NEW_HOSTNAME=$1

echo "==> [Debian] Ensuring hostname is set to ${NEW_HOSTNAME}..."
hostnamectl set-hostname "${NEW_HOSTNAME}"

# Prevent "unable to resolve host" warnings in Debian
if ! grep -q "${NEW_HOSTNAME}" /etc/hosts; then
    echo "127.0.0.1   ${NEW_HOSTNAME}" >> /etc/hosts
fi

echo "==> [Debian] Installing core dependencies non-interactively..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl sudo ufw iptables > /dev/null

echo "==> [Debian] Configuring 2GB Swap file for RAM safety margin..."
if ! grep -q '/swapfile' /etc/fstab; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile > /dev/null
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    # Keep Linux from swapping aggressively unless RAM is exhausted
    sysctl vm.swappiness=10
    echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
fi

echo "==> [Debian] Enabling IP Forwarding for K3s Container Networking..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-k3s-ipforward.conf
sysctl -p /etc/sysctl.d/99-k3s-ipforward.conf > /dev/null

echo "==> [Debian] Configuring UFW Firewall rules for K3s..."
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow 22/tcp comment 'SSH' > /dev/null
ufw allow 6443/tcp comment 'K3s API server' > /dev/null
ufw allow 8472/udp comment 'Flannel VXLAN overlay network' > /dev/null
ufw allow 10250/tcp comment 'Kubelet metrics' > /dev/null
ufw --force enable > /dev/null

echo "==> Bootstrapping complete for ${NEW_HOSTNAME}! Node is ready for K3s."