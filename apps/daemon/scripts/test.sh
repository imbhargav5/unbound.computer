#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Running Daemon Unit Tests ==="
echo ""

# Run all tests with output
cargo test --workspace -- --nocapture

echo ""
echo "=== Test Summary ==="
total=$(cargo test --workspace -- --list 2>/dev/null | grep -c "test$" || echo "0")
echo "Total tests: $total"

echo ""
echo "=== Coverage by Crate ==="
for crate in daemon-core daemon-storage daemon-database daemon-auth daemon-ipc armin deku piccolo levi toshinori yamcha yagami; do
    count=$(cargo test -p $crate -- --list 2>/dev/null | grep -c "test$" || echo "0")
    echo "  $crate: $count tests"
done
