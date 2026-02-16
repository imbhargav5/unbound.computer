#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Running Daemon Unit Tests ==="
echo ""

# Run workspace tests serially and skip piccolo integration tests in CI.
# `-j 1` avoids cross-crate fixture/socket contention on Linux CI.
cargo test --workspace --exclude piccolo -j 1 -- --nocapture --test-threads=1
# Keep piccolo library unit tests in coverage without the integration suites.
cargo test -p piccolo --lib -j 1 -- --nocapture --test-threads=1

echo ""
echo "=== Test Summary ==="
total=$(cargo test --workspace --exclude piccolo -- --list 2>/dev/null | grep -c "test$" || echo "0")
piccolo_total=$(cargo test -p piccolo --lib -- --list 2>/dev/null | grep -c "test$" || echo "0")
total=$((total + piccolo_total))
echo "Total tests: $total"

echo ""
echo "=== Coverage by Crate ==="
for crate in daemon-config-and-utils daemon-storage daemon-database daemon-auth daemon-ipc armin deku piccolo levi toshinori yamcha yagami; do
    count=$(cargo test -p $crate -- --list 2>/dev/null | grep -c "test$" || echo "0")
    echo "  $crate: $count tests"
done
