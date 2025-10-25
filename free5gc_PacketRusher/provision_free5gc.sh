#!/bin/bash
set -e  # Exit on error

echo "=== Starting free5GC Installation ==="

# Update and install prerequisites
echo "=== Installing Prerequisites ==="
sudo apt-get update
sudo apt-get install -y git wget curl gnupg

# Install Go
echo "=== Installing Go 1.24.5 ==="
cd ~
GO_VERSION="1.24.5"
wget https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -zxvf go${GO_VERSION}.linux-amd64.tar.gz
mkdir -p ~/go/{bin,pkg,src}

# Set Go environment variables
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export PATH=$PATH:$GOPATH/bin:$GOROOT/bin
export GO111MODULE=auto

# Add to .bashrc for future sessions
grep -qxF 'export GOPATH=$HOME/go' ~/.bashrc || echo 'export GOPATH=$HOME/go' >> ~/.bashrc
grep -qxF 'export GOROOT=/usr/local/go' ~/.bashrc || echo 'export GOROOT=/usr/local/go' >> ~/.bashrc
grep -qxF 'export PATH=$PATH:$GOPATH/bin:$GOROOT/bin' ~/.bashrc || echo 'export PATH=$PATH:$GOPATH/bin:$GOROOT/bin' >> ~/.bashrc
grep -qxF 'export GO111MODULE=auto' ~/.bashrc || echo 'export GO111MODULE=auto' >> ~/.bashrc

# Verify Go installation
go version

# Install MongoDB Community Edition for Ubuntu 22.04
echo "=== Installing MongoDB 7.0 ==="
cd ~
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org

# Start and enable MongoDB
sudo systemctl start mongod
sudo systemctl enable mongod
sudo systemctl status mongod --no-pager

# Install user-plane supporting packages
echo "=== Installing User-plane Supporting Packages ==="
sudo apt-get install -y gcc g++ cmake autoconf libtool pkg-config libmnl-dev libyaml-dev

# Configure Linux Host Network Settings
echo "=== Configuring Network Settings ==="
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400
sudo systemctl stop ufw || true
sudo systemctl disable ufw || true

# Install gtp5g
echo "=== Installing gtp5g Kernel Module ==="
cd ~
# Remove existing directory if present (for re-provisioning)
rm -rf gtp5g
git clone -b v0.9.14 https://github.com/free5gc/gtp5g.git
cd gtp5g
make
sudo make install
cd ~

# Clone and build free5GC
echo "=== Cloning and Building free5GC v4.0.0 ==="
cd ~
# Remove existing directory if present (for re-provisioning)
rm -rf free5gc_base
git clone --recursive -b v4.0.0 https://github.com/free5gc/free5gc.git free5gc_base
cd free5gc_base
make

# Install Node.js and build WebConsole
echo "=== Installing Node.js and Building WebConsole ==="
cd ~
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo corepack enable

# Build WebConsole
cd ~/free5gc_base
make webconsole

echo "=== free5GC Installation Completed Successfully ==="
echo "Installation directory: ~/free5gc_base"
echo "To start free5GC, run: cd ~/free5gc_base && ./run.sh"
