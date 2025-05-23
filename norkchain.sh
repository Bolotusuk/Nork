#!/bin/bash

# Automated script to install and run Nockchain
# Based on https://github.com/zorp-corp/nockchain and https://github.com/GzGod/nock/blob/main/nock-install.sh
# Runs on Debian/Ubuntu, assumes sudo privileges

# Exit on any error
set -e

# Variables
NOCKCHAIN_DIR="$HOME/nockchain"
PUBLIC_IP="158.220.120.168"
PEER_PORT="3006"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to perform system update
system_update() {
    echo "Updating system..."
    sudo apt update -y && sudo apt upgrade -y
}

# Function to install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    sudo apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libclang-dev llvm-dev
}

# Function to install Rust and Cargo
install_rust() {
    if ! command_exists rustup; then
        echo "Installing Rust and Cargo..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        rustup update
    else
        echo "Rust is already installed. Updating..."
        rustup update
    fi
    # Verify Cargo
    if ! command_exists cargo; then
        echo "Error: Cargo not found after Rust installation."
        exit 1
    fi
}

# Function to clone Nockchain and set up
setup_nockchain() {
    if [ -d "$NOCKCHAIN_DIR" ]; then
        echo "Nockchain directory exists. Pulling latest changes..."
        cd "$NOCKCHAIN_DIR"
        git pull
    else
        echo "Cloning Nockchain repository..."
        git clone https://github.com/zorp-corp/nockchain "$NOCKCHAIN_DIR"
        cd "$NOCKCHAIN_DIR"
    fi

    # Copy .env_example to .env if it doesn't exist
    if [ ! -f ".env" ]; then
        echo "Copying .env_example to .env..."
        cp .env_example .env
    fi

    # Set default logging in .env if not present
    if ! grep -q "RUST_LOG=" .env; then
        echo "Setting default logging in .env..."
        echo "RUST_LOG=info,nockchain=debug,nockchain_libp2p_io=info,libp2p=info,libp2p_quic=info" >> .env
        echo "MINIMAL_LOG_FORMAT=true" >> .env
    fi
}

# Function to generate and set MINING_PUBKEY
generate_keys() {
    echo "Generating new key pair..."
    KEYGEN_OUTPUT=$(nockchain-wallet keygen)
    PUBLIC_KEY=$(echo "$KEYGEN_OUTPUT" | grep "Public Key" | awk '{print $NF}')
    if [ -n "$PUBLIC_KEY" ]; then
        echo "Updating MINING_PUBKEY in .env..."
        if grep -q "MINING_PUBKEY=" .env; then
            sed -i "s/MINING_PUBKEY=.*/MINING_PUBKEY=$PUBLIC_KEY/" .env
        else
            echo "MINING_PUBKEY=$PUBLIC_KEY" >> .env
        fi
        echo "Public Key set: $PUBLIC_KEY"
        echo "Please save the seed phrase shown above for backup."
    else
        echo "Error: Could not extract public key. Please check nockchain-wallet keygen output."
        exit 1
    fi
}

# Function to build and install Nockchain
build_nockchain() {
    echo "Building Nockchain..."
    make install-hoonc
    export PATH="$HOME/.cargo/bin:$PATH"
    make build
    make install-nockchain-wallet
    make install-nockchain
}

# Function to check port 3006
check_port() {
    echo "Checking if port $PEER_PORT is open..."
    if nc -u -z -w 3 canyouseeme.org $PEER_PORT; then
        echo "Port $PEER_PORT is open."
    else
        echo "Warning: Port $PEER_PORT may be closed. Check your VPS firewall or contact your provider (e.g., Contabo)."
        echo "You may need to configure port forwarding or allow UDP $PEER_PORT."
    fi
}

# Function to run Nockchain node without mining
run_node() {
    echo "Running Nockchain node without mining..."
    cd "$NOCKCHAIN_DIR"
    source .env
    echo "Executing: nockchain --bind /ip4/$PUBLIC_IP/udp/$PEER_PORT/quic-v1"
    nockchain --bind /ip4/$PUBLIC_IP/udp/$PEER_PORT/quic-v1
}

# Function to run Nockchain miner
run_miner() {
    echo "Running Nockchain miner..."
    cd "$NOCKCHAIN_DIR"
    source .env
    echo "Executing: nockchain --bind /ip4/$PUBLIC_IP/udp/$PEER_PORT/quic-v1 --mine"
    nockchain --bind /ip4/$PUBLIC_IP/udp/$PEER_PORT/quic-v1 --mine
}

# Main menu
main_menu() {
    while true; do
        echo "====================================="
        echo "Nockchain Automation Script"
        echo "====================================="
        echo "1. Run Nockchain node (no mining)"
        echo "2. Run Nockchain miner"
        echo "3. Exit"
        echo "====================================="
        read -p "Select an option (1-3): " choice

        case $choice in
            1)
                run_node
                ;;
            2)
                run_miner
                ;;
            3)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option. Please choose 1, 2, or 3."
                ;;
        esac
    done
}

# Main execution
echo "Starting Nockchain installation and setup..."

# Step 1: System update
system_update

# Step 2: Install dependencies
install_dependencies

# Step 3: Install Rust and Cargo
install_rust

# Step 4: Setup Nockchain
setup_nockchain

# Step 5: Generate keys if MINING_PUBKEY is not set or invalid
if ! grep -q "MINING_PUBKEY=" .env || grep -q "MINING_PUBKEY=$" .env; then
    generate_keys
else
    echo "MINING_PUBKEY is already set in .env. Using existing key."
    grep "MINING_PUBKEY=" .env
fi

# Step 6: Build and install
build_nockchain

# Step 7: Check port
check_port

# Step 8: Show menu to run Nockchain
main_menu
