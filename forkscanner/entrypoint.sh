#!/bin/bash
set -euo pipefail

# Wait for postgres to be ready
echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U forkscanner -q; do
  sleep 1
done

# Run diesel migrations
echo "Running database migrations..."
diesel migration run

# Register the regtest bitcoin node in the database
echo "Registering bitcoin regtest node..."
PGPASSWORD=forkscanner psql -h postgres -U forkscanner -d forkscanner -c "
  INSERT INTO nodes (name, rpc_host, rpc_port, mirror_rpc_port, rpc_user, rpc_password, unreachable_since)
  SELECT 'bitcoin-regtest', 'bitcoin', 18443, NULL, 'bitcoin', 'pass', NULL
  WHERE NOT EXISTS (SELECT 1 FROM nodes WHERE name = 'bitcoin-regtest');
" 2>/dev/null || true

echo "Starting forkscanner..."
exec forkscanner --rpc 0.0.0.0:8339 --ws 0.0.0.0:8340 --all
