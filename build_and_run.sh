#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${JWT_SECRET:?Set JWT_SECRET to a random value of at least 32 bytes}"
command -v g++ >/dev/null || { echo 'g++ is required'; exit 1; }
command -v go >/dev/null || { echo 'Go is required'; exit 1; }
g++ -O2 -Wall -Wextra -Wpedantic -std=c++20 core/src/engine.cpp core/src/main.cpp -o core_engine -lrt
go -C gateway mod download
rm -f /dev/shm/varianth_exchange_shm
cleanup() { kill "${ENGINE_PID:-}" "${GATEWAY_PID:-}" 2>/dev/null || true; rm -f /dev/shm/varianth_exchange_shm; }
trap cleanup EXIT INT TERM
./core_engine & ENGINE_PID=$!
for _ in $(seq 1 50); do [[ -e /dev/shm/varianth_exchange_shm ]] && break; sleep 0.1; done
[[ -e /dev/shm/varianth_exchange_shm ]] || { echo 'engine did not create shared memory'; exit 1; }
(cd gateway && go run .) & GATEWAY_PID=$!
wait "$GATEWAY_PID"
