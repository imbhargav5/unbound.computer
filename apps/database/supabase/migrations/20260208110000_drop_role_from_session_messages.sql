-- Drop the role column from agent_coding_session_messages.
-- Role is now included within the encrypted message content,
-- so storing it as a separate plaintext column is redundant.

ALTER TABLE public.agent_coding_session_messages DROP COLUMN IF EXISTS role;
