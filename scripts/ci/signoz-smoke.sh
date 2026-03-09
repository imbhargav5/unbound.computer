#!/usr/bin/env bash

set -euo pipefail

WINDOW_SECONDS="${1:-900}"
CLICKHOUSE_CONTAINER="${CLICKHOUSE_CONTAINER:-signoz-clickhouse}"
DAEMON_LOG_PATH="${DAEMON_LOG_PATH:-$HOME/.unbound-dev/logs/dev.jsonl}"
EXPECTED_SERVICES="${EXPECTED_SERVICES:-daemon}"
REQUIRE_TRACES="${REQUIRE_TRACES:-0}"

run_clickhouse() {
  docker exec "$CLICKHOUSE_CONTAINER" clickhouse-client --query "$1"
}

echo "SigNoz smoke check"
echo "Window: ${WINDOW_SECONDS}s"
echo "Expected services: ${EXPECTED_SERVICES}"
echo "Require traces: ${REQUIRE_TRACES}"
echo

LOGS_QUERY="
SELECT
  resources_string['service.name'] AS service,
  count() AS rows,
  max(toDateTime(timestamp/1000000000)) AS last_seen
FROM signoz_logs.logs_v2
WHERE timestamp > (toUInt64(toUnixTimestamp(now()) - ${WINDOW_SECONDS}) * 1000000000)
  AND resources_string['service.name'] IN ('daemon', 'macos')
GROUP BY service
ORDER BY service
FORMAT TSVRaw
"

TRACES_QUERY="
SELECT
  serviceName AS service,
  count() AS spans,
  max(timestamp) AS last_seen
FROM signoz_traces.signoz_index_v3
WHERE timestamp > (now64(9) - toIntervalSecond(${WINDOW_SECONDS}))
  AND serviceName IN ('daemon', 'macos')
GROUP BY service
ORDER BY service
FORMAT TSVRaw
"

RESOURCE_QUERY="
SELECT DISTINCT string_value
FROM signoz_logs.tag_attributes_v2
WHERE tag_key='service.name'
ORDER BY string_value
FORMAT TSVRaw
"

logs_output="$(run_clickhouse "$LOGS_QUERY")"
traces_output="$(run_clickhouse "$TRACES_QUERY")"
resource_output="$(run_clickhouse "$RESOURCE_QUERY")"

echo "Recent log services:"
printf '%s\n' "$logs_output"
echo

echo "Recent trace services:"
printf '%s\n' "$traces_output"
echo

echo "Indexed service.name values:"
printf '%s\n' "$resource_output"
echo

missing=0

for service in ${EXPECTED_SERVICES//,/ }; do
  if ! printf '%s\n' "$logs_output" | rg -q "^${service}[[:space:]]"; then
    echo "Missing recent logs for service: ${service}" >&2
    missing=1
  fi
  if [ "$REQUIRE_TRACES" = "1" ] && ! printf '%s\n' "$traces_output" | rg -q "^${service}[[:space:]]"; then
    echo "Missing recent spans for service: ${service}" >&2
    missing=1
  fi
done

for service in ${EXPECTED_SERVICES//,/ }; do
  if ! printf '%s\n' "$resource_output" | rg -qx "$service"; then
    echo "Missing indexed service.name value: ${service}" >&2
    missing=1
  fi
done

if [ -f "$DAEMON_LOG_PATH" ]; then
  echo "Recent local daemon exporter warnings:"
  rg -n "BatchLogProcessor\\.Emit\\.AfterShutdown|there is no reactor running" "$DAEMON_LOG_PATH" | tail -n 10 || true
  echo
fi

if [ "$missing" -ne 0 ]; then
  echo "SigNoz smoke check failed" >&2
  exit 1
fi

echo "SigNoz smoke check passed"
