#!/bin/bash
set -euo pipefail

NODE_NAME="${NODE_NAME:?NODE_NAME env var is required}"
NODE_HOME="/testnet/${NODE_NAME}"

echo "Starting ${NODE_NAME} from ${NODE_HOME}..."
exec nyksd start --home "${NODE_HOME}"
