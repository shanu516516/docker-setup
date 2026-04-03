# Nyks Testnet Docker Setup

Local development environment for the Nyks chain with Bitcoin regtest, forkscanner, and btc-oracle.

## Prerequisites

- Docker and Docker Compose (v2)
- `nyksd` binary placed in this directory (the root `docker-setup/` folder)

## Quick Start

```bash
# 1. Place the nyksd binary in the project root
cp /path/to/nyksd ./nyksd

# 2. Build and start everything
docker compose up --build
```

That's it. All services start in the correct order automatically.

## Architecture

```
bitcoin (regtest)
    |
    +-- bitcoin-init          Creates 6 validator wallets + 1 "online" watch-only wallet
    |
postgres
    |
    +-- forkscanner           Monitors BTC chain, exposes RPC :8339 and WS :8340
    +-- oracle-db-init        Creates per-oracle databases with schema
    |
init (nyksd)                  Initializes 6-node testnet (genesis, keys, peers)
    |
    +-- validator-sfo         Primary validator (API :1317, RPC :26657)
    +-- validator-nyc
    +-- validator-lon
    +-- validator-sgp
    +-- validator-tor
    +-- validator-fra
         |
         +-- bootstrap        Sets delegate addresses, creates volt, registers signers
              |
              +-- oracle-sfo  BTC oracle (judge mode)
              +-- oracle-nyc  BTC oracle (signer mode)
              +-- oracle-lon  BTC oracle (signer mode)
              +-- oracle-sgp  BTC oracle (signer mode)
              +-- oracle-tok  BTC oracle (signer mode)
              +-- oracle-fra  BTC oracle (signer mode)
```

## Startup Order

1. **bitcoin** + **postgres** start
2. **bitcoin-init** creates 7 BTC wallets (6 validator + 1 online watch-only)
3. **forkscanner** connects to bitcoin and postgres, runs migrations, registers the regtest node
4. **init** initializes the nyks testnet (genesis, validator keys, persistent peers)
5. **6 validators** start and begin producing blocks
6. **bootstrap** runs once all validators are up:
   - Sets delegate addresses for all 6 validators (with BTC public keys from regtest wallets)
   - Judge (validator-sfo) bootstraps a fragment (params: 6 signers, threshold 5)
   - 5 signer validators submit signer-application
   - Judge accepts all 5 signers
7. **oracle-db-init** creates 6 databases (one per oracle) with the required schema
8. **6 btc-oracle instances** start after bootstrap and DB init complete

## Exposed Ports

| Port  | Service        | Description               |
|-------|----------------|---------------------------|
| 1317  | validator-sfo  | Cosmos REST API           |
| 26657 | validator-sfo  | Tendermint RPC            |
| 26656 | validator-sfo  | Tendermint P2P            |
| 18443 | bitcoin        | Bitcoin RPC (regtest)     |
| 8339  | forkscanner    | Forkscanner RPC           |
| 8340  | forkscanner    | Forkscanner WebSocket     |

## Useful Commands

```bash
# View logs for a specific service
docker compose logs -f oracle-sfo
docker compose logs -f bootstrap

# Check validator status
curl http://localhost:26657/status

# Query the chain via REST API
curl http://localhost:1317/cosmos/base/tendermint/v1beta1/blocks/latest

# Bitcoin RPC (regtest)
docker compose exec bitcoin bitcoin-cli -regtest -rpcuser=bitcoin -rpcpassword=pass getblockchaininfo

# List BTC wallets
docker compose exec bitcoin bitcoin-cli -regtest -rpcuser=bitcoin -rpcpassword=pass listwallets

# Connect to a postgres database
docker compose exec postgres psql -U forkscanner -d judge-validator-sfo

# Stop everything
docker compose down

# Stop and remove all data (full reset)
docker compose down -v
```

## Configuration

### Bitcoin
- Config: `bitcoin/bitcoin.conf`
- Network: regtest
- RPC credentials: `bitcoin` / `pass`

### Validators
- Chain ID: `nyks-test`
- Denom: `nyks-test`
- 6 validators with equal stake (100,000,000 nyks-test each)

### BTC Oracle
- Built from `fee-by-judge` branch of `github.com/twilight-project/btc-oracle`
- Config is auto-generated at startup per oracle instance
- Each oracle gets its own postgres database (`judge-validator-*`)
- `oracle-sfo` runs as judge, all others as signers

### Forkscanner
- Built from `github.com/twilight-project/forkscanner`
- Runs with `--all` flag
- Uses the shared postgres instance (database: `forkscanner`)

## Resetting

To do a full reset (wipe all chain data, wallets, and databases):

```bash
docker compose down -v
docker compose up --build
```

The `init`, `bootstrap`, `bitcoin-init`, and `oracle-db-init` services use marker files to skip re-initialization on restart. Removing volumes (`-v`) clears these markers.
