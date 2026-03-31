#!/bin/bash
set -euo pipefail

CHAIN_ID="nyks-test"
DENOM="nyks-test"
VALIDATORS=("validator-sfo" "validator-nyc" "validator-lon" "validator-sgp" "validator-tor" "validator-fra")
SENTRIES=("sentry-1" "sentry-2")
ALL_NODES=("${VALIDATORS[@]}" "${SENTRIES[@]}")
STAKE_AMOUNT="100000000${DENOM}"
ACCOUNT_BALANCE="200000000${DENOM}"
TESTNET_DIR="/testnet"

# Skip if already initialized
if [ -f "${TESTNET_DIR}/.initialized" ]; then
  echo "Testnet already initialized, skipping."
  exit 0
fi

echo "==> Initializing ${#VALIDATORS[@]}-validator, ${#SENTRIES[@]}-sentry testnet with chain-id: ${CHAIN_ID}"

# Step 1: Init all nodes (validators + sentries)
for NODE in "${ALL_NODES[@]}"; do
  NODE_HOME="${TESTNET_DIR}/${NODE}"
  echo "==> Initializing ${NODE} at ${NODE_HOME}"
  nyksd init "${NODE}" --chain-id "${CHAIN_ID}" --home "${NODE_HOME}" > /dev/null 2>&1
done

# Use first node (validator-sfo) as the genesis source
GENESIS_HOME="${TESTNET_DIR}/${VALIDATORS[0]}"
GENESIS_FILE="${GENESIS_HOME}/config/genesis.json"

# Step 2: Update genesis denom from stake to our denom
sed -i "s/\"stake\"/\"${DENOM}\"/g" "${GENESIS_FILE}"

# Step 3: Create validator accounts and add genesis accounts
for i in "${!VALIDATORS[@]}"; do
  NODE_HOME="${TESTNET_DIR}/${VALIDATORS[$i]}"
  KEYNAME="${VALIDATORS[$i]}"

  # Create key
  nyksd keys add "${KEYNAME}" --keyring-backend test --home "${NODE_HOME}" > /dev/null 2>&1

  # Get address
  ADDR=$(nyksd keys show "${KEYNAME}" --keyring-backend test --home "${NODE_HOME}" -a)

  # Add genesis account to the source genesis
  nyksd add-genesis-account "${ADDR}" "${ACCOUNT_BALANCE}" --home "${GENESIS_HOME}" --keyring-backend test
done

# Step 4: Create gentxs
for i in "${!VALIDATORS[@]}"; do
  NODE_HOME="${TESTNET_DIR}/${VALIDATORS[$i]}"
  KEYNAME="${VALIDATORS[$i]}"

  # Copy current genesis to this node so gentx can validate against it
  if [ "$i" -ne 0 ]; then
    cp "${GENESIS_FILE}" "${NODE_HOME}/config/genesis.json"
  fi

  nyksd gentx "${KEYNAME}" "${STAKE_AMOUNT}" \
    --chain-id "${CHAIN_ID}" \
    --keyring-backend test \
    --home "${NODE_HOME}" > /dev/null 2>&1
done

# Step 5: Collect all gentxs into the genesis node
for i in "${!VALIDATORS[@]}"; do
  if [ "$i" -eq 0 ]; then continue; fi
  NODE_HOME="${TESTNET_DIR}/${VALIDATORS[$i]}"
  cp "${NODE_HOME}/config/gentx/"*.json "${GENESIS_HOME}/config/gentx/"
done

nyksd collect-gentxs --home "${GENESIS_HOME}" > /dev/null 2>&1
nyksd validate-genesis --home "${GENESIS_HOME}"

# Step 6: Build peer ID maps
# Sentry peers string (for validators to connect to)
SENTRY_PEERS=""
for SENTRY in "${SENTRIES[@]}"; do
  SENTRY_HOME="${TESTNET_DIR}/${SENTRY}"
  SENTRY_ID=$(nyksd tendermint show-node-id --home "${SENTRY_HOME}")
  if [ -n "${SENTRY_PEERS}" ]; then
    SENTRY_PEERS="${SENTRY_PEERS},"
  fi
  SENTRY_PEERS="${SENTRY_PEERS}${SENTRY_ID}@${SENTRY}:26656"
done

# Validator peers string (for sentries to know about)
VALIDATOR_PEERS=""
VALIDATOR_IDS=""
for VAL in "${VALIDATORS[@]}"; do
  VAL_HOME="${TESTNET_DIR}/${VAL}"
  VAL_ID=$(nyksd tendermint show-node-id --home "${VAL_HOME}")
  if [ -n "${VALIDATOR_PEERS}" ]; then
    VALIDATOR_PEERS="${VALIDATOR_PEERS},"
    VALIDATOR_IDS="${VALIDATOR_IDS},"
  fi
  VALIDATOR_PEERS="${VALIDATOR_PEERS}${VAL_ID}@${VAL}:26656"
  VALIDATOR_IDS="${VALIDATOR_IDS}${VAL_ID}"
done

# Step 7: Configure validator nodes
# Validators connect ONLY to sentry nodes, pex disabled
for i in "${!VALIDATORS[@]}"; do
  NODE_HOME="${TESTNET_DIR}/${VALIDATORS[$i]}"
  NODE_NAME="${VALIDATORS[$i]}"
  APP_TOML="${NODE_HOME}/config/app.toml"
  CONFIG_TOML="${NODE_HOME}/config/config.toml"

  # Copy final genesis to all validators
  if [ "$i" -ne 0 ]; then
    cp "${GENESIS_FILE}" "${NODE_HOME}/config/genesis.json"
  fi

  # Validators only connect to sentry nodes
  sed -i "s/^persistent_peers *=.*/persistent_peers = \"${SENTRY_PEERS}\"/" "${CONFIG_TOML}"

  # Disable PEX on validators (they only talk to sentries)
  sed -i 's/^pex *=.*/pex = false/' "${CONFIG_TOML}"

  # Listen on all interfaces
  sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/' "${CONFIG_TOML}"
  sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26656"/laddr = "tcp:\/\/0.0.0.0:26656"/' "${CONFIG_TOML}"

  # Enable remote signer (TMKMS) on port 26659
  sed -i 's/^priv_validator_laddr *=.*/priv_validator_laddr = "tcp:\/\/0.0.0.0:26659"/' "${CONFIG_TOML}"

  # Set minimum-gas-prices
  sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0${DENOM}\"/" "${APP_TOML}"

  # --- validator-sfo only: extra config ---
  if [ "${NODE_NAME}" = "validator-sfo" ]; then
    sed -i 's/^cors_allowed_origins *=.*/cors_allowed_origins = ["*"]/' "${CONFIG_TOML}"
    sed -i 's/^prometheus *=.*/prometheus = true/' "${CONFIG_TOML}"

    sed -i '/^\[api\]/,/^\[/ {
      s/^enable *=.*/enable = true/
      s/^enabled-unsafe-cors *=.*/enabled-unsafe-cors = true/
    }' "${APP_TOML}"

    sed -i 's|^address = "tcp://localhost:1317"|address = "tcp://0.0.0.0:1317"|' "${APP_TOML}"
  fi
done

# Step 8: Configure sentry nodes
# Sentries connect to each other and all validators, pex enabled
# Sentries hide validator node IDs via private_peer_ids
for SENTRY in "${SENTRIES[@]}"; do
  SENTRY_HOME="${TESTNET_DIR}/${SENTRY}"
  APP_TOML="${SENTRY_HOME}/config/app.toml"
  CONFIG_TOML="${SENTRY_HOME}/config/config.toml"

  # Copy final genesis
  cp "${GENESIS_FILE}" "${SENTRY_HOME}/config/genesis.json"

  # Build peer list: all validators + other sentry (exclude self)
  SELF_ID=$(nyksd tendermint show-node-id --home "${SENTRY_HOME}")
  OTHER_SENTRY=$(echo "${SENTRY_PEERS}" | sed "s/${SELF_ID}@${SENTRY}:26656,\?//g" | sed 's/,$//')

  ALL_SENTRY_PEERS="${VALIDATOR_PEERS}"
  if [ -n "${OTHER_SENTRY}" ]; then
    ALL_SENTRY_PEERS="${ALL_SENTRY_PEERS},${OTHER_SENTRY}"
  fi

  sed -i "s/^persistent_peers *=.*/persistent_peers = \"${ALL_SENTRY_PEERS}\"/" "${CONFIG_TOML}"

  # Enable PEX on sentries
  sed -i 's/^pex *=.*/pex = true/' "${CONFIG_TOML}"

  # Hide validator IDs from other peers
  sed -i "s/^private_peer_ids *=.*/private_peer_ids = \"${VALIDATOR_IDS}\"/" "${CONFIG_TOML}"

  # Listen on all interfaces
  sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/' "${CONFIG_TOML}"
  sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26656"/laddr = "tcp:\/\/0.0.0.0:26656"/' "${CONFIG_TOML}"

  # Set minimum-gas-prices
  sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0${DENOM}\"/" "${APP_TOML}"
done

touch "${TESTNET_DIR}/.initialized"
echo "==> Testnet initialization complete!"
echo "==> Validators: ${VALIDATORS[*]}"
echo "==> Sentries: ${SENTRIES[*]}"
echo "==> Chain ID: ${CHAIN_ID}"
