#!/usr/bin/env bash
set -euo pipefail

WORKSPACES=(
  "apps/daemon"
  "apps/cli-new"
  "packages/observability"
)

print_workspaces() {
  for workspace in "${WORKSPACES[@]}"; do
    echo "${workspace}"
  done
}

print_cache_targets() {
  for workspace in "${WORKSPACES[@]}"; do
    echo "${workspace} -> target"
  done
}

run_fmt() {
  for workspace in "${WORKSPACES[@]}"; do
    (
      cd "${workspace}"
      cargo fmt --check
    )
  done
}

run_clippy() {
  for workspace in "${WORKSPACES[@]}"; do
    (
      cd "${workspace}"
      if [[ "${workspace}" == "apps/daemon" ]]; then
        cargo clippy --workspace -- -D warnings
      else
        cargo clippy -- -D warnings
      fi
    )
  done
}

run_test() {
  for workspace in "${WORKSPACES[@]}"; do
    (
      cd "${workspace}"
      if [[ "${workspace}" == "apps/daemon" ]]; then
        cargo test --workspace
      else
        cargo test
      fi
    )
  done
}

run_all() {
  run_fmt
  run_clippy
  run_test
}

command=${1:-all}

case "${command}" in
  list)
    print_workspaces
    ;;
  cache-targets)
    print_cache_targets
    ;;
  fmt)
    run_fmt
    ;;
  clippy)
    run_clippy
    ;;
  test)
    run_test
    ;;
  all)
    run_all
    ;;
  *)
    echo "Unknown command: ${command}" >&2
    echo "Usage: $0 {list|cache-targets|fmt|clippy|test|all}" >&2
    exit 1
    ;;
 esac
