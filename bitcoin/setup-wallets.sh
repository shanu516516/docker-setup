#!/bin/bash
set -euo pipefail

RPC_USER="bitcoin"
RPC_PASS="pass"
CLI="bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser=${RPC_USER} -rpcpassword=${RPC_PASS}"

# Wait for bitcoin node to be ready
echo "Waiting for Bitcoin regtest node..."
until ${CLI} getblockchaininfo > /dev/null 2>&1; do
  sleep 1
done
echo "Bitcoin node is ready."

# Ensure a wallet is loaded, creating it if it doesn't exist
# Usage: ensure_wallet <name> [create_args...]
ensure_wallet() {
  local name="$1"; shift
  # Check if already loaded
  if ${CLI} listwallets 2>/dev/null | jq -e --arg w "${name}" 'index($w) != null' > /dev/null 2>&1; then
    echo "Wallet '${name}' already loaded."
    return 0
  fi
  # Try loading from disk
  if ${CLI} loadwallet "${name}" > /dev/null 2>&1; then
    echo "Wallet '${name}' loaded from disk."
    return 0
  fi
  # Create new wallet
  echo "Creating wallet '${name}'..."
  ${CLI} createwallet "${name}" "$@"
  echo "  Wallet '${name}' created."
}

WALLETS=("validator-sfo" "validator-nyc" "validator-lon" "validator-sgp" "validator-tor" "validator-fra")

for WALLET in "${WALLETS[@]}"; do
  ensure_wallet "${WALLET}" false false "" false true
done

# Watch-only wallet (no private keys)
ensure_wallet "online" true true "" false false

# Fee wallet
ensure_wallet "fee" false false "" false true

echo "==> All wallets ready."
