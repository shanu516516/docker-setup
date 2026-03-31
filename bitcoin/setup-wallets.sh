#!/bin/bash
set -euo pipefail

RPC_URL="http://bitcoin:18443"
RPC_USER="bitcoin"
RPC_PASS="pass"

WALLETS=("validator-sfo" "validator-nyc" "validator-lon" "validator-sgp" "validator-tor" "validator-fra")

# Wait for bitcoin node to be ready
echo "Waiting for Bitcoin regtest node..."
until bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser="${RPC_USER}" -rpcpassword="${RPC_PASS}" getblockchaininfo > /dev/null 2>&1; do
  sleep 1
done
echo "Bitcoin node is ready."

for WALLET in "${WALLETS[@]}"; do
  # Check if wallet already exists
  if bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser="${RPC_USER}" -rpcpassword="${RPC_PASS}" loadwallet "${WALLET}" 2>/dev/null; then
    echo "Wallet '${WALLET}' already exists, loaded."
  else
    echo "Creating descriptor wallet '${WALLET}'..."
    bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser="${RPC_USER}" -rpcpassword="${RPC_PASS}" \
      createwallet "${WALLET}" false false "" false true
    echo "  Wallet '${WALLET}' created."
  fi
done

# Create watch-only wallet "online" (no private keys, blank descriptor — descriptors will be imported by btc-oracle)
if bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser="${RPC_USER}" -rpcpassword="${RPC_PASS}" loadwallet "online" 2>/dev/null; then
  echo "Wallet 'online' already exists, loaded."
else
  echo "Creating watch-only wallet 'online'..."
  bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser="${RPC_USER}" -rpcpassword="${RPC_PASS}" \
    createwallet "online" true true "" false false
  echo "  Wallet 'online' created (watch-only, no private keys)."
fi

# Create fee wallet
if bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser="${RPC_USER}" -rpcpassword="${RPC_PASS}" loadwallet "fee" 2>/dev/null; then
  echo "Wallet 'fee' already exists, loaded."
else
  echo "Creating descriptor wallet 'fee'..."
  bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser="${RPC_USER}" -rpcpassword="${RPC_PASS}" \
    createwallet "fee" false false "" false true
  echo "  Wallet 'fee' created."
fi

echo "==> All wallets created."
