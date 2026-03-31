FROM rust:1.70-bullseye AS builder

RUN apt-get update && apt-get install -y libpq-dev && rm -rf /var/lib/apt/lists/*
RUN cargo install diesel_cli --no-default-features --features postgres

RUN git clone https://github.com/twilight-project/forkscanner.git /forkscanner
WORKDIR /forkscanner
RUN cargo build --release

FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y libpq5 postgresql-client && rm -rf /var/lib/apt/lists/*

COPY --from=builder /forkscanner/target/release/forkscanner /usr/local/bin/forkscanner
COPY --from=builder /usr/local/cargo/bin/diesel /usr/local/bin/diesel
COPY --from=builder /forkscanner/migrations /forkscanner/migrations
COPY --from=builder /forkscanner/diesel.toml /forkscanner/diesel.toml
COPY --from=builder /forkscanner/scripts /forkscanner/scripts

COPY entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh

WORKDIR /forkscanner
ENTRYPOINT ["/scripts/entrypoint.sh"]
