#!/bin/bash
set -euo pipefail

NODE_NAME="${NODE_NAME:?NODE_NAME is required}"
TESTNET_DIR="/testnet"
NODE_HOME="${TESTNET_DIR}/${NODE_NAME}"
KMS_HOME="/tmkms/${NODE_NAME}"

# Wait for testnet initialization
echo "[tmkms-${NODE_NAME}] Waiting for testnet initialization..."
until [ -f "${TESTNET_DIR}/.initialized" ]; do
  sleep 2
done
echo "[tmkms-${NODE_NAME}] Testnet initialized."

# Skip if already set up
if [ -f "${KMS_HOME}/tmkms.toml" ]; then
  echo "[tmkms-${NODE_NAME}] Already configured, starting..."
  exec tmkms start -c "${KMS_HOME}/tmkms.toml"
fi

# Set up TMKMS home
mkdir -p "${KMS_HOME}/secrets"

# Import the validator's private key to softsign format
echo "[tmkms-${NODE_NAME}] Importing validator key..."
tmkms softsign import "${NODE_HOME}/config/priv_validator_key.json" \
  "${KMS_HOME}/secrets/consensus-ed25519.key"

# Generate secret connection key
tmkms softsign keygen "${KMS_HOME}/secrets/kms-identity.key"

# Generate config
cat > "${KMS_HOME}/tmkms.toml" <<EOF
[[chain]]
id = "nyks-test"
key_format = { type = "bech32", account_key_prefix = "twilightpub", consensus_key_prefix = "twilightvalconspub" }
state_file = "${KMS_HOME}/state/priv_validator_state.json"

[[validator]]
addr = "tcp://${NODE_NAME}:26659"
chain_id = "nyks-test"
reconnect = true
secret_key = "${KMS_HOME}/secrets/kms-identity.key"
protocol_version = "v0.34"

[[providers.softsign]]
chain_ids = ["nyks-test"]
key_type = "consensus"
path = "${KMS_HOME}/secrets/consensus-ed25519.key"
EOF

# Create state directory
mkdir -p "${KMS_HOME}/state"

echo "[tmkms-${NODE_NAME}] Config generated:"
cat "${KMS_HOME}/tmkms.toml"

echo "[tmkms-${NODE_NAME}] Starting TMKMS..."
exec tmkms start -c "${KMS_HOME}/tmkms.toml"
