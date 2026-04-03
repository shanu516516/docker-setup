#!/bin/bash
set -euo pipefail

CHAIN_ID="nyks-test"
TESTNET_DIR="/testnet"
JUDGE_NODE="validator-sfo"
NODES=("validator-sfo" "validator-nyc" "validator-lon" "validator-sgp" "validator-tor" "validator-fra")
SIGNER_NODES=("validator-nyc" "validator-lon" "validator-sgp" "validator-tor" "validator-fra")

BTC_RPC_URL="http://bitcoin:bitcoin%40pass@bitcoin:18443"

# Helper: call bitcoin JSON-RPC
btc_rpc() {
  local wallet="$1"
  local method="$2"
  shift 2
  local params="${1:-[]}"
  curl -sf --user bitcoin:pass \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"1.0\",\"method\":\"${method}\",\"params\":${params}}" \
    "http://bitcoin:18443/wallet/${wallet}"
}

# Skip if already bootstrapped
if [ -f "${TESTNET_DIR}/.bootstrapped" ]; then
  echo "Bootstrap already completed, skipping."
  exit 0
fi

# Wait for testnet initialization
echo "Waiting for testnet initialization..."
until [ -f "${TESTNET_DIR}/.initialized" ]; do
  sleep 2
done
echo "Testnet initialized."

# Wait for bitcoin wallets to be ready
echo "Waiting for Bitcoin wallets..."
until btc_rpc "${JUDGE_NODE}" "getwalletinfo" > /dev/null 2>&1; do
  sleep 2
done
echo "Bitcoin wallets ready."

# Wait for validator-sfo API to be ready
echo "Waiting for validator-sfo API..."
until curl -sf "http://validator-sfo:1317/cosmos/base/tendermint/v1beta1/blocks/latest" > /dev/null 2>&1; do
  sleep 2
done
echo "Validator API is ready."

# Give the chain a few more seconds to stabilize
sleep 10

# ============================================================
# Helper: extract BTC public key from a wallet's descriptors
# Uses the second-to-last descriptor's pubkey
# ============================================================
get_btc_pubkey() {
  local wallet="$1"
  # Generate a new address and extract its compressed public key
  local addr
  addr=$(btc_rpc "${wallet}" "getnewaddress" | jq -r '.result')
  btc_rpc "${wallet}" "getaddressinfo" "[\"${addr}\"]" | jq -r '.result.pubkey'
}

# ============================================================
# Step 1: Set delegate addresses for all validators
# ============================================================
echo "==> Step 1: Setting delegate addresses for all validators"

for NODE in "${NODES[@]}"; do
  NODE_HOME="${TESTNET_DIR}/${NODE}"
  VALOPER=$(nyksd keys show "${NODE}" --keyring-backend test --home "${NODE_HOME}" --bech val -a)
  OWN_ADDR=$(nyksd keys show "${NODE}" --keyring-backend test --home "${NODE_HOME}" -a)
  BTC_PUBKEY=$(get_btc_pubkey "${NODE}")

  echo "  Setting delegate for ${NODE} (btc pubkey: ${BTC_PUBKEY})..."
  nyksd tx nyks set-delegate-addresses \
    "${VALOPER}" "${OWN_ADDR}" "${BTC_PUBKEY}" "${OWN_ADDR}" \
    --from "${NODE}" \
    --chain-id "${CHAIN_ID}" \
    --keyring-backend test \
    --home "${NODE_HOME}" \
    --node "tcp://validator-sfo:26657" \
    -y
  sleep 6
done

echo "==> All delegate addresses set."

# ============================================================
# Step 2: Judge (validator-sfo) bootstraps fragment
# ============================================================
echo "==> Step 2: Bootstrapping fragment from ${JUDGE_NODE}"

JUDGE_HOME="${TESTNET_DIR}/${JUDGE_NODE}"
JUDGE_ADDR=$(nyksd keys show "${JUDGE_NODE}" --keyring-backend test --home "${JUDGE_HOME}" -a)

nyksd tx bridge bootstrap-fragment \
  "${JUDGE_ADDR}" 6 5 1 1 22 \
  --from "${JUDGE_NODE}" \
  --chain-id "${CHAIN_ID}" \
  --keyring-backend test \
  --home "${JUDGE_HOME}" \
  --node "tcp://validator-sfo:26657" \
  -y
sleep 6

echo "==> Fragment bootstrapped."

# ============================================================
# Step 3: Signers submit signer-application
# ============================================================
echo "==> Step 3: Submitting signer applications"

for NODE in "${SIGNER_NODES[@]}"; do
  NODE_HOME="${TESTNET_DIR}/${NODE}"
  BTC_PUBKEY=$(get_btc_pubkey "${NODE}")

  echo "  Submitting signer application for ${NODE}..."
  nyksd tx volt signer-application \
    1 1 1 "${BTC_PUBKEY}" \
    --from "${NODE}" \
    --chain-id "${CHAIN_ID}" \
    --keyring-backend test \
    --home "${NODE_HOME}" \
    --node "tcp://validator-sfo:26657" \
    -y
  sleep 6
done

echo "==> All signer applications submitted."

# ============================================================
# Step 4: Judge accepts all signers
# ============================================================
echo "==> Step 4: Judge accepting signers"

for i in $(seq 1 ${#SIGNER_NODES[@]}); do
  echo "  Accepting signer ${i}..."
  nyksd tx volt accept-signers \
    1 "${i}" \
    --from "${JUDGE_NODE}" \
    --chain-id "${CHAIN_ID}" \
    --keyring-backend test \
    --home "${JUDGE_HOME}" \
    --node "tcp://validator-sfo:26657" \
    -y
  sleep 6
done

echo "==> All signers accepted."

touch "${TESTNET_DIR}/.bootstrapped"
echo "==> Bootstrap complete!"
