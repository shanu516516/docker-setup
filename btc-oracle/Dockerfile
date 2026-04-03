FROM golang:1.22 AS builder

RUN git clone -b reverse-iterators https://github.com/twilight-project/nyks.git /nyks
RUN git clone -b fee-by-judge https://github.com/twilight-project/btc-oracle.git /app
WORKDIR /app
RUN go mod tidy && go build -o btc-oracle .

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash sed jq curl ca-certificates postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/btc-oracle /usr/local/bin/btc-oracle
COPY nyksd /usr/local/bin/nyksd
RUN chmod +x /usr/local/bin/btc-oracle /usr/local/bin/nyksd

COPY scripts/setup-testnet.sh /scripts/setup-testnet.sh
COPY scripts/bootstrap.sh /scripts/bootstrap.sh
COPY btc-oracle/entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/*.sh

WORKDIR /app
ENTRYPOINT ["/scripts/entrypoint.sh"]
