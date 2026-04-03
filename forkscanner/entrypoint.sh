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
  INSERT INTO nodes (node, rpc_host, rpc_port, rpc_user, rpc_pass)
  SELECT 'bitcoin-regtest', 'bitcoin', 18443, 'bitcoin', 'pass'
  WHERE NOT EXISTS (SELECT 1 FROM nodes WHERE node = 'bitcoin-regtest');
" 2>/dev/null || true

echo "Starting forkscanner..."
echo "DATABASE_URL=${DATABASE_URL}" > /forkscanner/.env
exec forkscanner --rpc 8339 --ws 8340
