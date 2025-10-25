#!/usr/bin/env bash
# Note: avoid 'set -u' (nounset) because some non-interactive shells
# source root's shell startup which may reference PS1 and fail when
# PS1 isn't defined. See Vagrant provisioning error: PS1: unbound variable
set -eo pipefail

# Provision script extracted from Vagrantfile inline shell provisioner.
# Run as the vagrant user (Vagrant runs provisioners as the SSH user by default).

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y build-essential linux-headers-generic linux-modules-extra-$(uname -r) make git wget tar

if ! command -v go >/dev/null 2>&1; then
  wget https://go.dev/dl/go1.24.1.linux-amd64.tar.gz
  sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.24.1.linux-amd64.tar.gz
  # Add to .profile for future sessions
  echo 'export PATH=$PATH:/usr/local/go/bin' >> "$HOME/.profile"
  # Export for current session (source doesn't work in non-interactive shells)
  export PATH=$PATH:/usr/local/go/bin
  echo "Go installed: $(go version)"
fi

if [ ! -d "$HOME/PacketRusher" ]; then
  git clone https://github.com/HewlettPackard/PacketRusher "$HOME/PacketRusher"
  echo "PacketRusher cloned to $HOME/PacketRusher"
fi

cd "$HOME/PacketRusher"
export PACKETRUSHER="$PWD"
# Add to .profile for future sessions
echo "export PACKETRUSHER=$PWD" >> "$HOME/.profile"
echo "PACKETRUSHER set to: $PACKETRUSHER"

# Build gtp5g kernel module
if [ -d "$PACKETRUSHER/lib/gtp5g" ]; then
  cd "$PACKETRUSHER/lib/gtp5g"
  make clean && make && sudo make install
fi

# Build PacketRusher
cd "$PACKETRUSHER"
if [ -f go.mod ]; then
  echo "Downloading Go dependencies..."
  go mod download
fi
echo "Building PacketRusher..."
go build cmd/packetrusher.go
echo "PacketRusher built successfully: $(ls -lh packetrusher)"

export PATH="$PATH:$PACKETRUSHER"
echo "export PATH=\$PATH:$PACKETRUSHER" >> "$HOME/.profile"
echo "PATH updated. PacketRusher is ready to use!"
