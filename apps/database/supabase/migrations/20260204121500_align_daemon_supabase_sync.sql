-- Align daemon Supabase writes with current schema expectations.

-- Add missing column for session secrets payloads.
ALTER TABLE public.agent_coding_session_secrets
  ADD COLUMN IF NOT EXISTS ephemeral_public_key text NOT NULL DEFAULT '';

-- Ensure repository upserts can use (device_id, local_path) conflict target.
CREATE UNIQUE INDEX IF NOT EXISTS idx_repositories_device_local_path
  ON public.repositories (device_id, local_path);

-- Optional: promote the unique index to a named constraint.
-- ALTER TABLE public.repositories
--   ADD CONSTRAINT repositories_device_id_local_path_key
--   UNIQUE USING INDEX idx_repositories_device_local_path;
