FROM rust:1.89 AS builder

RUN apt-get update && apt-get install -y libusb-1.0-0-dev pkg-config && rm -rf /var/lib/apt/lists/*

RUN cargo install tmkms --features=softsign --version=0.15.0

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libusb-1.0-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/cargo/bin/tmkms /usr/local/bin/tmkms
COPY entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
