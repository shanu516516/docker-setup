FROM golang:1.22 AS builder

RUN git clone -b fee-by-judge https://github.com/twilight-project/btc-oracle.git /app
RUN git clone -b clearingv03 https://github.com/twilight-project/nyks.git /nyks
WORKDIR /app
RUN go mod tidy && go build -o btc-oracle .

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    jq curl ca-certificates postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/btc-oracle /usr/local/bin/btc-oracle
COPY nyksd /usr/local/bin/nyksd
COPY btc-oracle/entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /usr/local/bin/btc-oracle /usr/local/bin/nyksd /scripts/entrypoint.sh

WORKDIR /app
ENTRYPOINT ["/scripts/entrypoint.sh"]
