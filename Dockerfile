FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends bash sed jq curl ca-certificates && rm -rf /var/lib/apt/lists/*

COPY nyksd /usr/local/bin/nyksd
RUN chmod +x /usr/local/bin/nyksd

COPY scripts/setup-testnet.sh /scripts/setup-testnet.sh
COPY scripts/bootstrap.sh /scripts/bootstrap.sh
COPY scripts/entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
