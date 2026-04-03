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

# ============================================================
# Start nyksd validator in the background
# ============================================================
echo "Starting ${NODE_NAME} validator..."
nyksd start --home "${NODE_HOME}" &
NYKSD_PID=$!

# Wait for validator RPC to be ready (localhost since same container)
echo "Waiting for validator RPC on localhost:26657..."
until curl -sf "http://localhost:26657/status" > /dev/null 2>&1; do
  sleep 2
done
echo "Validator RPC is ready."

# ============================================================
# Wait for bootstrap to complete before starting oracle
# ============================================================
echo "Waiting for bootstrap to complete..."
until [ -f "${TESTNET_DIR}/.bootstrapped" ]; do
  sleep 3
done
echo "Bootstrap complete."

# ============================================================
# Oracle setup
# ============================================================

# Wait for postgres
echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U forkscanner -q; do
  sleep 1
done
echo "PostgreSQL is ready."

# Extract addresses from nyksd keyring
OWN_ADDRESS=$(nyksd keys show "${NODE_NAME}" --keyring-backend test --home "${NODE_HOME}" -a)
OWN_VALOPER=$(nyksd keys show "${NODE_NAME}" --keyring-backend test --home "${NODE_HOME}" --bech val -a)

# Always extract judge (validator-sfo) address
JUDGE_ADDRESS=$(nyksd keys show "validator-sfo" --keyring-backend test --home "${TESTNET_DIR}/validator-sfo" -a)

# Wait for bitcoin wallet to be loaded
until curl -sf --user bitcoin:pass -H "Content-Type: application/json" \
  -d '{"jsonrpc":"1.0","method":"getwalletinfo","params":[]}' \
  "http://bitcoin:18443/wallet/${NODE_NAME}" > /dev/null 2>&1; do
  sleep 2
done

DESCRIPTORS=$(curl -sf --user bitcoin:pass -H "Content-Type: application/json" \
  -d '{"jsonrpc":"1.0","method":"listdescriptors","params":[]}' \
  "http://bitcoin:18443/wallet/${NODE_NAME}")

# Extract the xpub descriptor (second-to-last)
BTC_XPUBLIC_KEY=$(echo "${DESCRIPTORS}" | jq -r '.result.descriptors[-2].desc' | sed 's/^wpkh(\(.*\))#.*$/\1/')

# Extract the compressed public key via getaddressinfo
BTC_ADDR=$(curl -sf --user bitcoin:pass -H "Content-Type: application/json" \
  -d '{"jsonrpc":"1.0","method":"getnewaddress","params":[]}' \
  "http://bitcoin:18443/wallet/${NODE_NAME}" | jq -r '.result')
BTC_PUBLIC_KEY=$(curl -sf --user bitcoin:pass -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"1.0\",\"method\":\"getaddressinfo\",\"params\":[\"${BTC_ADDR}\"]}" \
  "http://bitcoin:18443/wallet/${NODE_NAME}" | jq -r '.result.pubkey')

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
    "nyksd_socket_url": "ws://localhost:26657/websocket",
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

# Unload wallets so btc-oracle can load them itself (avoids lock errors)
unload_wallet() {
  curl -sf --user bitcoin:pass -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"1.0\",\"method\":\"unloadwallet\",\"params\":[\"$1\"]}" \
    "http://bitcoin:18443" > /dev/null 2>&1 || true
}

unload_wallet "${NODE_NAME}"

if [ "${RUNNING_MODE}" = "judge" ]; then
  unload_wallet "fee"
  unload_wallet "online"
fi

sleep 2

# ============================================================
# Start btc-oracle (foreground) and monitor nyksd
# ============================================================
echo "Starting btc-oracle..."
btc-oracle &
ORACLE_PID=$!

# Wait for either process to exit
wait -n ${NYKSD_PID} ${ORACLE_PID} 2>/dev/null || true

# If one exits, kill the other and exit
echo "A process exited, shutting down..."
kill ${NYKSD_PID} ${ORACLE_PID} 2>/dev/null || true
wait
exit 1
