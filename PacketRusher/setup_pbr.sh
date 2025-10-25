#!/bin/bash

# Policy-Based Routing (PBR) Setup Script
# Purpose: Route traffic from UEs-VM (192.168.121.50) to 10.0.0.0/8 via eno2 with NAT
# Usage: 
#   Setup:  ./setup_pbr.sh
#   Delete: ./setup_pbr.sh -D

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load configuration from pbr_config.env
CONFIG_FILE="$(dirname "$0")/pbr_config.env"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}Loading configuration from: ${CONFIG_FILE}${NC}"
    source "$CONFIG_FILE"
    echo -e "${GREEN}✓ Configuration loaded${NC}"
    echo -e "  • UEs-VM IP: ${UES_VM_IP}"
    echo -e "  • ENO2 Interface: ${ENO2_INTERFACE} (${ENO2_IP})"
    echo -e "  • Gateway: ${GATEWAY_IP}"
    echo -e "  • Destination Network: ${DEST_NETWORK}"
    echo -e "  • Routing Table: ${RT_TABLE_NAME} (ID: ${RT_TABLE_ID})"
else
    echo -e "${RED}Error: Configuration file not found: ${CONFIG_FILE}${NC}"
    echo -e "${RED}Please create pbr_config.env with required settings.${NC}"
    exit 1
fi

# Parse command line arguments first
DELETE_MODE=false
if [ "$1" == "-D" ]; then
    DELETE_MODE=true
fi

# Get UEs-VM IP from Vagrantfile or running VM
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAGRANTFILE="${SCRIPT_DIR}/Vagrantfile"

# Function to get UEs-VM IP
get_ues_vm_ip() {
    # Prefer value from configuration or environment if present
    if [ -n "$UES_VM_IP" ]; then
        echo "$UES_VM_IP"
        return
    fi

    # Otherwise try to parse the Vagrantfile for the configured private_network IP
    if [ -f "$VAGRANTFILE" ]; then
        # Look for lines like: ip: "192.168.121.50"
        local parsed_ip
        parsed_ip=$(grep -oE 'ip:\s*"[0-9\.]+"' "$VAGRANTFILE" | head -1 | sed -E 's/ip:\s*"([0-9\.]+)"/\1/')
        if [ -n "$parsed_ip" ]; then
            echo "$parsed_ip"
            return
        fi
    fi

    # If nothing found, return empty string
    echo ""
}

echo -e "${YELLOW}Detecting UEs-VM IP address...${NC}"
UES_VM_IP=$(get_ues_vm_ip)

if [ -z "$UES_VM_IP" ]; then
    echo -e "${RED}Error: Could not detect UEs-VM IP address!${NC}"
    echo -e "${YELLOW}Please ensure:${NC}"
    echo -e "  1. The Vagrant VM is running, or"
    echo -e "  2. The Vagrantfile exists in the same directory as this script"
    echo -e "\n${YELLOW}You can also manually specify the IP:${NC}"
    echo -e "  UES_VM_IP=192.168.121.50 sudo -E $0 $1"
    exit 1
fi

echo -e "${GREEN}✓ Detected UEs-VM IP: ${UES_VM_IP}${NC}\n"

# Function to delete all PBR configurations
delete_pbr_config() {
    echo -e "${YELLOW}=== Deleting Policy-Based Routing Configuration ===${NC}"
    
    # Step 1: Remove NAT rules
    echo -e "\n${YELLOW}[Step 1]${NC} Removing NAT rules..."
    if sudo iptables -t nat -C POSTROUTING -s "${UES_VM_IP}" -o "${ENO2_INTERFACE}" -j SNAT --to-source "${ENO2_IP_ONLY}" 2>/dev/null; then
        sudo iptables -t nat -D POSTROUTING -s "${UES_VM_IP}" -o "${ENO2_INTERFACE}" -j SNAT --to-source "${ENO2_IP_ONLY}"
        echo -e "${GREEN}✓ NAT rule removed${NC}"
    else
        echo -e "${YELLOW}• No NAT rule found${NC}"
    fi
    
    # Step 2: Remove policy routing rule
    echo -e "\n${YELLOW}[Step 2]${NC} Removing policy routing rule..."
    if sudo ip rule del from "${UES_VM_IP}" to "${DEST_NETWORK}" table "${RT_TABLE_NAME}" 2>/dev/null; then
        echo -e "${GREEN}✓ Policy rule removed${NC}"
    else
        echo -e "${YELLOW}• No policy rule found${NC}"
    fi
    
    # Step 3: Remove routes from custom table
    echo -e "\n${YELLOW}[Step 3]${NC} Removing routes from custom table..."
    if sudo ip route del "${DEST_NETWORK}" via "${GATEWAY_IP}" dev "${ENO2_INTERFACE}" table "${RT_TABLE_NAME}" 2>/dev/null; then
        echo -e "${GREEN}✓ Route removed${NC}"
    else
        echo -e "${YELLOW}• No route found in table${NC}"
    fi
    
    # Step 4: Flush the entire routing table (optional, to be thorough)
    echo -e "\n${YELLOW}[Step 4]${NC} Flushing routing table '${RT_TABLE_NAME}'..."
    sudo ip route flush table "${RT_TABLE_NAME}" 2>/dev/null || true
    echo -e "${GREEN}✓ Routing table flushed${NC}"
    
    # Step 5: Remove routing table from /etc/iproute2/rt_tables
    echo -e "\n${YELLOW}[Step 5]${NC} Removing routing table from /etc/iproute2/rt_tables..."
    if grep -q "^${RT_TABLE_ID}\s*${RT_TABLE_NAME}" /etc/iproute2/rt_tables; then
        sudo sed -i "/^${RT_TABLE_ID}\s*${RT_TABLE_NAME}/d" /etc/iproute2/rt_tables
        echo -e "${GREEN}✓ Routing table entry removed${NC}"
    else
        echo -e "${YELLOW}• Routing table entry not found${NC}"
    fi
    
    # Step 6: Optionally remove IP from eno2 (commented out by default)
    echo -e "\n${YELLOW}[Step 6]${NC} IP address on ${ENO2_INTERFACE}..."
    if ip addr show "${ENO2_INTERFACE}" | grep -q "${ENO2_IP_ONLY}"; then
        echo -e "${YELLOW}Note: IP ${ENO2_IP} is still configured on ${ENO2_INTERFACE}${NC}"
        echo -e "${YELLOW}To remove it manually, run: sudo ip addr del ${ENO2_IP} dev ${ENO2_INTERFACE}${NC}"
        # Uncomment the following lines if you want to automatically remove the IP:
        # sudo ip addr del "${ENO2_IP}" dev "${ENO2_INTERFACE}" 2>/dev/null || true
        # echo -e "${GREEN}✓ IP address removed${NC}"
    else
        echo -e "${GREEN}✓ IP address not configured${NC}"
    fi
    
    echo -e "\n${GREEN}=== Deletion Complete ===${NC}"
    echo -e "${GREEN}All PBR configurations have been removed.${NC}"
    
    exit 0
}

# Check if we're in delete mode
if [ "$DELETE_MODE" = true ]; then
    delete_pbr_config
fi

echo -e "${GREEN}=== Policy-Based Routing Setup ===${NC}"

# Step 1: Check if eno2 interface exists
echo -e "\n${YELLOW}[Step 1]${NC} Checking if interface ${ENO2_INTERFACE} exists..."
if ! ip link show "${ENO2_INTERFACE}" &> /dev/null; then
    echo -e "${RED}Error: Interface ${ENO2_INTERFACE} does not exist!${NC}"
    echo "Available interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/:$//'
    exit 1
fi
echo -e "${GREEN}✓ Interface ${ENO2_INTERFACE} exists${NC}"

# Step 2: Configure IP address on eno2 if not already configured
echo -e "\n${YELLOW}[Step 2]${NC} Checking IP configuration on ${ENO2_INTERFACE}..."
if ip addr show "${ENO2_INTERFACE}" | grep -q "${ENO2_IP_ONLY}"; then
    echo -e "${GREEN}✓ IP ${ENO2_IP} already configured on ${ENO2_INTERFACE}${NC}"
else
    echo -e "${YELLOW}Configuring IP ${ENO2_IP} on ${ENO2_INTERFACE}...${NC}"
    sudo ip addr add "${ENO2_IP}" dev "${ENO2_INTERFACE}"
    sudo ip link set "${ENO2_INTERFACE}" up
    echo -e "${GREEN}✓ IP address configured${NC}"
fi

# Step 3: Create custom routing table
echo -e "\n${YELLOW}[Step 3]${NC} Setting up custom routing table..."

# Add routing table to /etc/iproute2/rt_tables if not already present
if ! grep -q "^${RT_TABLE_ID}\s*${RT_TABLE_NAME}" /etc/iproute2/rt_tables; then
    echo -e "${YELLOW}Adding routing table '${RT_TABLE_NAME}' (ID: ${RT_TABLE_ID}) to /etc/iproute2/rt_tables...${NC}"
    echo "${RT_TABLE_ID} ${RT_TABLE_NAME}" | sudo tee -a /etc/iproute2/rt_tables > /dev/null
    echo -e "${GREEN}✓ Routing table added${NC}"
else
    echo -e "${GREEN}✓ Routing table '${RT_TABLE_NAME}' already exists${NC}"
fi

# Step 4: Configure routing rules in the custom table
echo -e "\n${YELLOW}[Step 4]${NC} Configuring routing rules..."

# Add default route via eno2 gateway in the custom table
echo -e "${YELLOW}Adding route to ${DEST_NETWORK} via ${GATEWAY_IP} in table ${RT_TABLE_NAME}...${NC}"
# Remove existing route if present to avoid duplicates
sudo ip route del "${DEST_NETWORK}" via "${GATEWAY_IP}" dev "${ENO2_INTERFACE}" table "${RT_TABLE_NAME}" 2>/dev/null || true
sudo ip route add "${DEST_NETWORK}" via "${GATEWAY_IP}" dev "${ENO2_INTERFACE}" table "${RT_TABLE_NAME}"
echo -e "${GREEN}✓ Route added${NC}"

# Step 5: Add policy routing rule for traffic from UEs-VM
echo -e "\n${YELLOW}[Step 5]${NC} Setting up policy routing rule..."
echo -e "${YELLOW}Creating rule: traffic from ${UES_VM_IP} to ${DEST_NETWORK} uses table ${RT_TABLE_NAME}...${NC}"

# Remove existing rule if present to avoid duplicates
sudo ip rule del from "${UES_VM_IP}" to "${DEST_NETWORK}" table "${RT_TABLE_NAME}" 2>/dev/null || true
sudo ip rule add from "${UES_VM_IP}" to "${DEST_NETWORK}" table "${RT_TABLE_NAME}"
echo -e "${GREEN}✓ Policy rule added${NC}"

# Step 6: Enable IP forwarding and NAT
echo -e "\n${YELLOW}[Step 6]${NC} Enabling IP forwarding and NAT..."

# Enable IP forwarding
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo -e "${YELLOW}Enabling IP forwarding...${NC}"
    sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
    echo -e "${GREEN}✓ IP forwarding enabled${NC}"
else
    echo -e "${GREEN}✓ IP forwarding already enabled${NC}"
fi

# Set up NAT (SNAT) for traffic going out via eno2
echo -e "${YELLOW}Setting up NAT for traffic from ${UES_VM_IP} via ${ENO2_INTERFACE}...${NC}"
# Check if iptables rule already exists
if ! sudo iptables -t nat -C POSTROUTING -s "${UES_VM_IP}" -o "${ENO2_INTERFACE}" -j SNAT --to-source "${ENO2_IP_ONLY}" 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -s "${UES_VM_IP}" -o "${ENO2_INTERFACE}" -j SNAT --to-source "${ENO2_IP_ONLY}"
    echo -e "${GREEN}✓ NAT rule added${NC}"
else
    echo -e "${GREEN}✓ NAT rule already exists${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Configuration Complete ===${NC}"
echo -e "Summary:"
echo -e "  • Interface: ${ENO2_INTERFACE} (${ENO2_IP})"
echo -e "  • Custom routing table: ${RT_TABLE_NAME} (ID: ${RT_TABLE_ID})"
echo -e "  • Traffic from: ${UES_VM_IP}"
echo -e "  • To destination: ${DEST_NETWORK}"
echo -e "  • Via gateway: ${GATEWAY_IP}"
echo -e "  • NAT source IP: ${ENO2_IP_ONLY}"

# Display current configuration
echo -e "\n${YELLOW}Current routing table '${RT_TABLE_NAME}':${NC}"
sudo ip route show table "${RT_TABLE_NAME}"

echo -e "\n${YELLOW}Current policy routing rules:${NC}"
sudo ip rule list | grep -A1 -B1 "${RT_TABLE_NAME}" || echo "No rules found"

echo -e "\n${YELLOW}Current NAT rules:${NC}"
sudo iptables -t nat -L POSTROUTING -n -v | grep "${UES_VM_IP}" || echo "No NAT rules found"

echo -e "\n${GREEN}Setup complete! Traffic from ${UES_VM_IP} to ${DEST_NETWORK} will be routed via ${ENO2_INTERFACE}.${NC}"
