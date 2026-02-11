#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SOURCE_DB="$HOME/Library/Application Support/com.unbound.macos/unbound.sqlite"
DEFAULT_OUTPUT_FILE="$SCRIPT_DIR/../unbound-ios/Resources/PreviewFixtures/session-detail-max-messages.json"

SOURCE_DB="${1:-$DEFAULT_SOURCE_DB}"
OUTPUT_FILE="${2:-$DEFAULT_OUTPUT_FILE}"
EXPORTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ ! -f "$SOURCE_DB" ]]; then
    echo "error: SQLite database not found at: $SOURCE_DB" >&2
    exit 1
fi

SESSION_COUNT="$(sqlite3 "$SOURCE_DB" "SELECT COUNT(*) FROM agent_coding_sessions;")"
if [[ "$SESSION_COUNT" == "0" ]]; then
    echo "error: no rows found in agent_coding_sessions" >&2
    exit 1
fi

SAFE_SOURCE_DB="${SOURCE_DB//\'/\'\'}"
SAFE_EXPORTED_AT="${EXPORTED_AT//\'/\'\'}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

sqlite3 "$SOURCE_DB" "
WITH top_session AS (
    SELECT
        s.id,
        s.title,
        s.status,
        s.created_at,
        s.last_accessed_at,
        COUNT(m.id) AS message_count
    FROM agent_coding_sessions s
    LEFT JOIN agent_coding_session_messages m
        ON m.session_id = s.id
    GROUP BY s.id
    ORDER BY message_count DESC, s.last_accessed_at DESC
    LIMIT 1
),
ordered_messages AS (
    SELECT
        m.id,
        m.sequence_number,
        m.timestamp,
        m.content
    FROM agent_coding_session_messages m
    JOIN top_session t
        ON t.id = m.session_id
    ORDER BY m.sequence_number ASC
)
SELECT json_object(
    'metadata',
    json_object(
        'source_db_path', '$SAFE_SOURCE_DB',
        'exported_at', '$SAFE_EXPORTED_AT',
        'selected_session_id', (SELECT id FROM top_session),
        'selected_message_count', (SELECT message_count FROM top_session)
    ),
    'session',
    json_object(
        'id', (SELECT id FROM top_session),
        'title', (SELECT title FROM top_session),
        'status', (SELECT status FROM top_session),
        'created_at', (SELECT created_at FROM top_session),
        'last_accessed_at', (SELECT last_accessed_at FROM top_session)
    ),
    'messages',
    COALESCE(
        (
            SELECT json_group_array(
                json_object(
                    'id', id,
                    'sequence_number', sequence_number,
                    'timestamp', timestamp,
                    'content', content
                )
            )
            FROM (
                SELECT
                    id,
                    sequence_number,
                    timestamp,
                    content
                FROM ordered_messages
                ORDER BY sequence_number ASC
            )
        ),
        json('[]')
    )
);
" > "$OUTPUT_FILE"

if [[ ! -s "$OUTPUT_FILE" ]]; then
    echo "error: fixture file was not generated: $OUTPUT_FILE" >&2
    exit 1
fi

SELECTED_SESSION_ID="$(
    sqlite3 "$SOURCE_DB" "
    SELECT s.id
    FROM agent_coding_sessions s
    LEFT JOIN agent_coding_session_messages m ON m.session_id = s.id
    GROUP BY s.id
    ORDER BY COUNT(m.id) DESC, s.last_accessed_at DESC
    LIMIT 1;
    "
)"
SELECTED_MESSAGE_COUNT="$(
    sqlite3 "$SOURCE_DB" "
    SELECT COUNT(*)
    FROM agent_coding_session_messages
    WHERE session_id = '$SELECTED_SESSION_ID';
    "
)"

echo "Exported fixture: $OUTPUT_FILE"
echo "Session ID: $SELECTED_SESSION_ID"
echo "Message count: $SELECTED_MESSAGE_COUNT"
