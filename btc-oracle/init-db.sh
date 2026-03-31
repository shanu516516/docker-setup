#!/bin/bash
set -euo pipefail

echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U forkscanner -q; do
  sleep 1
done
echo "PostgreSQL is ready."

DATABASES=(
  "judge-validator-sfo"
  "judge-validator-nyc"
  "judge-validator-lon"
  "judge-validator-sgp"
  "judge-validator-tor"
  "judge-validator-fra"
)

SCHEMA='
CREATE TABLE IF NOT EXISTS address (
  address VARCHAR NOT NULL,
  script BYTEA NOT NULL,
  preimage BYTEA NOT NULL,
  unlock_height BIGINT,
  parent_address VARCHAR,
  signed_refund BOOLEAN,
  signed_sweep BOOLEAN,
  archived BOOLEAN,
  broadcast_sweep BOOLEAN,
  broadcast_refund BOOLEAN,
  owned BOOLEAN
);

CREATE TABLE IF NOT EXISTS notification (
  block VARCHAR NOT NULL,
  receiving VARCHAR NOT NULL,
  satoshis BIGINT NOT NULL,
  height BIGINT NOT NULL,
  txid VARCHAR NOT NULL,
  archived BOOLEAN,
  sending VARCHAR,
  receiving_vout BIGINT,
  sending_vout BIGINT
);

CREATE TABLE IF NOT EXISTS proposed_address (
  current VARCHAR NOT NULL,
  proposed VARCHAR NOT NULL,
  unlock_height BIGINT,
  reserve_id BIGINT,
  round_id BIGINT
);

CREATE TABLE IF NOT EXISTS signed_tx (
  tx BYTEA NOT NULL,
  unlock_height BIGINT
);

CREATE TABLE IF NOT EXISTS transaction (
  txid VARCHAR NOT NULL,
  address VARCHAR,
  reserve BIGINT,
  round BIGINT,
  watched BOOLEAN
);

CREATE TABLE IF NOT EXISTS unsigned_sweep_tx (
  tx VARCHAR,
  reserve_id INTEGER,
  round_id INTEGER
);

CREATE TABLE IF NOT EXISTS unsigned_refund_tx (
  tx VARCHAR,
  reserve_id INTEGER,
  round_id INTEGER
);
'

for DB_NAME in "${DATABASES[@]}"; do
  echo "Creating database '${DB_NAME}'..."
  psql -h postgres -U forkscanner -c "CREATE DATABASE \"${DB_NAME}\";" 2>/dev/null || echo "  Database '${DB_NAME}' already exists."

  echo "  Creating schema for '${DB_NAME}'..."
  psql -h postgres -U forkscanner -d "${DB_NAME}" -c "${SCHEMA}"
done

echo "==> All oracle databases created with schema."
