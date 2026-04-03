#!/bin/bash
set -euo pipefail

CLI="bitcoin-cli -regtest -rpcconnect=bitcoin -rpcport=18443 -rpcuser=bitcoin -rpcpassword=pass"

echo "Waiting for Bitcoin node..."
until ${CLI} getblockchaininfo > /dev/null 2>&1; do
  sleep 1
done

# Skip if blocks already exist
BLOCKS=$(${CLI} getblockcount)
if [ "${BLOCKS}" -gt 100 ]; then
  echo "Already ${BLOCKS} blocks, skipping."
  exit 0
fi

echo "Mining initial blocks and generating fee history..."
ADDR=$(${CLI} -rpcwallet=fee getnewaddress)

# Mine 101 blocks to mature coinbase
${CLI} -rpcwallet=fee generatetoaddress 101 "${ADDR}" > /dev/null

# Generate transactions + blocks for fee estimation
for i in $(seq 1 25); do
  for j in $(seq 1 5); do
    ${CLI} -rpcwallet=fee sendtoaddress "${ADDR}" 0.001 > /dev/null 2>&1 || true
  done
  ${CLI} -rpcwallet=fee generatetoaddress 1 "${ADDR}" > /dev/null
done

echo "==> Mined $(${CLI} getblockcount) blocks with fee history."
