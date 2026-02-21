-- Add title column to agent_coding_sessions for session rename support.
ALTER TABLE public.agent_coding_sessions
  ADD COLUMN IF NOT EXISTS title text;

COMMENT ON COLUMN public.agent_coding_sessions.title IS 'User-defined session title for cross-device rename support.';
