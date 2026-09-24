# Varianth Coin Exchange Core

This repository contains a **non-production reference implementation** of a non-custodial exchange-engine prototype: a C++ matching loop and a Go HTTP gateway connected through a POSIX shared-memory single-producer/single-consumer queue.

> **Important:** This is not a regulated-exchange implementation and must not be used with real funds. It intentionally omits custody, settlement, authentication, market surveillance, durable order state, liquidation auctions, reconciliation, and regulatory controls. Obtain legal, security, and financial-market reviews before any deployment.

## Layout

```text
core/include/engine.hpp
core/src/engine.cpp
core/src/main.cpp
gateway/main.go
gateway/go.mod
build_and_run.sh
```

## Local demo

Linux is required for POSIX shared memory.

```bash
./build_and_run.sh
```

In another terminal:

```bash
curl -X POST http://127.0.0.1:8080/api/v1/order/submit \
  -H 'Content-Type: application/json' \
  -d '{"user_id":1001,"price":64500,"quantity":0.01,"side":0,"type":0}'
```

The prototype rejects malformed values, uses integer price/quantity scaling, binds to loopback, and uses a bounded SPSC queue. It does **not** provide authentication or authorization and must remain local-only.

## Production blockers

Before considering a real exchange, replace this prototype with reviewed components for identity/MFA, durable event sourcing, encrypted account and collateral ledgers, deterministic risk and settlement, market-data integrity, cancel/replace, replay protection, rate limits, audit retention, key management, observability, disaster recovery, compliance, penetration testing, and formal/fuzz/property testing. Do not treat the demo's margin or liquidation logic as financially safe.
