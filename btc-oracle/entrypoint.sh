#!/bin/bash
set -euo pipefail

NODE_NAME="${NODE_NAME:?NODE_NAME is required}"
RUNNING_MODE="${RUNNING_MODE:?RUNNING_MODE is required}"

TESTNET_DIR="/testnet"
NODE_HOME="${TESTNET_DIR}/${NODE_NAME}"

# Wait for testnet initialization
echo "Waiting for testnet initialization..."
until [ -f "${TESTNET_DIR}/.initialized" ]; do
  sleep 2
done
echo "Testnet initialized."

# Wait for postgres
echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U forkscanner -q; do
  sleep 1
done
echo "PostgreSQL is ready."

# Wait for the validator node RPC
echo "Waiting for ${NODE_NAME} RPC..."
until curl -sf "http://${NODE_NAME}:26657/status" > /dev/null 2>&1; do
  sleep 2
done
echo "${NODE_NAME} RPC is ready."

# Extract addresses from nyksd keyring
OWN_ADDRESS=$(nyksd keys show "${NODE_NAME}" --keyring-backend test --home "${NODE_HOME}" -a)
OWN_VALOPER=$(nyksd keys show "${NODE_NAME}" --keyring-backend test --home "${NODE_HOME}" --bech val -a)

# Always extract judge (validator-sfo) address
JUDGE_ADDRESS=$(nyksd keys show "validator-sfo" --keyring-backend test --home "${TESTNET_DIR}/validator-sfo" -a)

# Extract BTC xpublic key and public key from wallet descriptors
# Wait for bitcoin wallet to be loaded
until curl -sf --user bitcoin:pass -H "Content-Type: application/json" \
  -d '{"jsonrpc":"1.0","method":"getwalletinfo","params":[]}' \
  "http://bitcoin:18443/wallet/${NODE_NAME}" > /dev/null 2>&1; do
  sleep 2
done

DESCRIPTORS=$(curl -sf --user bitcoin:pass -H "Content-Type: application/json" \
  -d '{"jsonrpc":"1.0","method":"listdescriptors","params":[]}' \
  "http://bitcoin:18443/wallet/${NODE_NAME}")

# Extract the xpub descriptor (second-to-last) - extract content inside wpkh() without checksum
# e.g. wpkh([dc0f2128/84h/0h/0h]xpub.../0/*)#checksum -> [dc0f2128/84h/0h/0h]xpub.../0/*
BTC_XPUBLIC_KEY=$(echo "${DESCRIPTORS}" | jq -r '.result.descriptors[-2].desc' | sed 's/^wpkh(\(.*\))#.*$/\1/')

# Extract the compressed public key (66-char hex) from the descriptor
BTC_PUBLIC_KEY=$(echo "${BTC_XPUBLIC_KEY}" | grep -oP '\]\K[0-9a-fA-F]{66}')

echo "Own address: ${OWN_ADDRESS}"
echo "Validator address: ${OWN_VALOPER}"
echo "Judge address: ${JUDGE_ADDRESS}"
echo "BTC xpublic key: ${BTC_XPUBLIC_KEY}"
echo "BTC public key: ${BTC_PUBLIC_KEY}"
echo "Running mode: ${RUNNING_MODE}"

# Generate config
mkdir -p /app/configs
cat > /app/configs/config.json <<EOF
{
    "accountName": "${NODE_NAME}",

    "DB_port": "5432",
    "DB_host": "postgres",
    "DB_user": "forkscanner",
    "DB_password": "forkscanner",
    "DB_name": "judge-${NODE_NAME}",

    "forkscanner_host": "forkscanner",
    "forkscanner_ws_port": "8340",
    "forkscanner_rpc_port": "8339",

    "nyksd_url": "http://validator-sfo:1317",
    "nyksd_socket_url": "ws://${NODE_NAME}:26657/websocket",
    "confirmation_limit": "3",

    "unlocking_time": "10",
    "sweep_preblock": "3",
    "running_mode": "${RUNNING_MODE}",
    "judge_address": "${JUDGE_ADDRESS}",
    "validator": "true",
    "own_validator_address": "${OWN_VALOPER}",
    "own_address": "${OWN_ADDRESS}",

    "btc_node_host": "bitcoin:18443",
    "btc_node_user": "bitcoin",
    "btc_node_pass": "pass",
    "wallet_name": "${NODE_NAME}",
    "fee_wallet_name": "fee",
    "judge_btc_wallet_name": "online",
    "btc_xpublic_key": "${BTC_XPUBLIC_KEY}",
    "btc_public_key": "${BTC_PUBLIC_KEY}"
}
EOF

echo "Config generated:"
cat /app/configs/config.json

exec btc-oracle
