#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Running Daemon Unit Tests ==="
echo ""

# Run workspace tests serially and skip git-ops integration tests in CI.
# `-j 1` avoids cross-crate fixture/socket contention on Linux CI.
cargo test --workspace --exclude git-ops -j 1 -- --nocapture --test-threads=1
# Keep git-ops library unit tests in coverage without the integration suites.
cargo test -p git-ops --lib -j 1 -- --nocapture --test-threads=1

echo ""
echo "=== Test Summary ==="
total=$(cargo test --workspace --exclude git-ops -- --list 2>/dev/null | grep -c "test$" || echo "0")
git_ops_total=$(cargo test -p git-ops --lib -- --list 2>/dev/null | grep -c "test$" || echo "0")
total=$((total + git_ops_total))
echo "Total tests: $total"

echo ""
echo "=== Coverage by Crate ==="
for crate in daemon-config-and-utils daemon-storage daemon-database daemon-auth daemon-ipc agent-session-sqlite-persist-core deku git-ops levi toshinori session-title-generator safe-repo-dir-lister; do
    count=$(cargo test -p $crate -- --list 2>/dev/null | grep -c "test$" || echo "0")
    echo "  $crate: $count tests"
done
