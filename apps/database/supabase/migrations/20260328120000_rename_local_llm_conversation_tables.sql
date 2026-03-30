-- Rename agent coding session tables to local LLM conversation naming.

DO $$
BEGIN
  IF to_regclass('public.agent_coding_sessions') IS NOT NULL
     AND to_regclass('public.local_llm_conversations') IS NULL THEN
    ALTER TABLE public.agent_coding_sessions RENAME TO local_llm_conversations;
  END IF;

  IF to_regclass('public.agent_coding_session_messages') IS NOT NULL
     AND to_regclass('public.local_llm_conversation_messages') IS NULL THEN
    ALTER TABLE public.agent_coding_session_messages RENAME TO local_llm_conversation_messages;
  END IF;

  IF to_regclass('public.agent_coding_session_secrets') IS NOT NULL
     AND to_regclass('public.local_llm_conversation_secrets') IS NULL THEN
    ALTER TABLE public.agent_coding_session_secrets RENAME TO local_llm_conversation_secrets;
  END IF;
END
$$;

DO $$
BEGIN
  IF to_regclass('public.idx_agent_coding_sessions_device_id') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_device_id
      RENAME TO idx_local_llm_conversations_device_id;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_device_status') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_device_status
      RENAME TO idx_local_llm_conversations_device_status;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_is_worktree') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_is_worktree
      RENAME TO idx_local_llm_conversations_is_worktree;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_last_heartbeat') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_last_heartbeat
      RENAME TO idx_local_llm_conversations_last_heartbeat;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_repo_worktree') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_repo_worktree
      RENAME TO idx_local_llm_conversations_repo_worktree;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_repository_id') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_repository_id
      RENAME TO idx_local_llm_conversations_repository_id;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_status') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_status
      RENAME TO idx_local_llm_conversations_status;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_user_id') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_user_id
      RENAME TO idx_local_llm_conversations_user_id;
  END IF;
  IF to_regclass('public.idx_agent_coding_sessions_user_status') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_sessions_user_status
      RENAME TO idx_local_llm_conversations_user_status;
  END IF;

  IF to_regclass('public.idx_agent_coding_session_messages_session_id') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_session_messages_session_id
      RENAME TO idx_local_llm_conversation_messages_session_id;
  END IF;
  IF to_regclass('public.idx_agent_coding_session_messages_session_sequence') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_session_messages_session_sequence
      RENAME TO idx_local_llm_conversation_messages_session_sequence;
  END IF;

  IF to_regclass('public.idx_agent_coding_session_secrets_session_device') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_session_secrets_session_device
      RENAME TO idx_local_llm_conversation_secrets_session_device;
  END IF;
  IF to_regclass('public.idx_agent_coding_session_secrets_session_id') IS NOT NULL THEN
    ALTER INDEX public.idx_agent_coding_session_secrets_session_id
      RENAME TO idx_local_llm_conversation_secrets_session_id;
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS ONLY public.agent_coding_sessions;
    ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.local_llm_conversations;
  END IF;
END
$$;
