#!/usr/bin/env bash
set -euo pipefail

WORKSPACES=(
  "apps/daemon"
  "apps/cli-new"
  "packages/observability"
)

workspace_filter=""
if [[ ${1:-} == "--workspace" ]]; then
  workspace_filter=${2:-}
  shift 2
fi

selected_workspaces=("${WORKSPACES[@]}")
if [[ -n "${workspace_filter}" ]]; then
  selected_workspaces=("${workspace_filter}")
fi

print_workspaces() {
  for workspace in "${selected_workspaces[@]}"; do
    echo "${workspace}"
  done
}

print_cache_targets() {
  for workspace in "${selected_workspaces[@]}"; do
    echo "${workspace} -> target"
  done
}

run_fmt() {
  for workspace in "${selected_workspaces[@]}"; do
    (
      cd "${workspace}"
      cargo fmt --check
    )
  done
}

run_clippy() {
  for workspace in "${selected_workspaces[@]}"; do
    (
      cd "${workspace}"
      if [[ "${workspace}" == "apps/daemon" ]]; then
        cargo clippy --workspace
      else
        cargo clippy
      fi
    )
  done
}

run_test() {
  for workspace in "${selected_workspaces[@]}"; do
    (
      cd "${workspace}"
      if [[ "${workspace}" == "apps/daemon" ]]; then
        cargo test --workspace --exclude piccolo -- --test-threads=1
        cargo test -p piccolo --lib -- --test-threads=1
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
    echo "Usage: $0 [--workspace <path>] {list|cache-targets|fmt|clippy|test|all}" >&2
    exit 1
    ;;
 esac
