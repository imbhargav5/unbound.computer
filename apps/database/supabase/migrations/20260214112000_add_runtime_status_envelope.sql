-- Add grouped runtime status envelope to agent_coding_sessions.

ALTER TABLE public.agent_coding_sessions
  ADD COLUMN IF NOT EXISTS runtime_status jsonb,
  ADD COLUMN IF NOT EXISTS runtime_status_updated_at timestamp with time zone;

UPDATE public.agent_coding_sessions
SET
  runtime_status = jsonb_build_object(
    'schema_version', 1,
    'coding_session', jsonb_build_object('status', 'not-available'),
    'device_id', device_id::text,
    'session_id', id::text,
    'updated_at_ms', (extract(epoch FROM coalesce(updated_at, session_started_at, created_at)) * 1000)::bigint
  ),
  runtime_status_updated_at = coalesce(updated_at, session_started_at, created_at)
WHERE runtime_status IS NULL;

ALTER TABLE public.agent_coding_sessions
  ADD CONSTRAINT agent_coding_sessions_runtime_status_shape_check
  CHECK (
    runtime_status IS NULL
    OR (
      jsonb_typeof(runtime_status) = 'object'
      AND (runtime_status ->> 'schema_version') = '1'
      AND jsonb_typeof(runtime_status -> 'coding_session') = 'object'
      AND (runtime_status -> 'coding_session' ->> 'status') IN ('running', 'idle', 'waiting', 'not-available', 'error')
      AND jsonb_typeof(runtime_status -> 'device_id') = 'string'
      AND jsonb_typeof(runtime_status -> 'session_id') = 'string'
      AND (runtime_status ->> 'session_id') = id::text
      AND jsonb_typeof(runtime_status -> 'updated_at_ms') = 'number'
      AND (
        (runtime_status -> 'coding_session' ? 'error_message') = false
        OR jsonb_typeof(runtime_status -> 'coding_session' -> 'error_message') = 'string'
      )
    )
  );

ALTER TABLE public.agent_coding_sessions
  ADD CONSTRAINT agent_coding_sessions_runtime_status_timestamp_check
  CHECK (runtime_status IS NULL OR runtime_status_updated_at IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_agent_coding_sessions_runtime_status_updated_at
  ON public.agent_coding_sessions (runtime_status_updated_at DESC);
