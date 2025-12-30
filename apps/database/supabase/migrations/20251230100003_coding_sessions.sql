/*
 * CODING SESSIONS TABLE
 *
 * Tracks active Claude Code sessions running in repositories.
 * Enables two-way communication between CLI and mobile app.
 * Realtime enabled for mobile push updates.
 */

CREATE TABLE IF NOT EXISTS public.coding_sessions (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
  repository_id UUID NOT NULL REFERENCES public.repositories(id) ON DELETE CASCADE,

  -- Session information
  session_pid INTEGER,
  session_started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  session_ended_at TIMESTAMP WITH TIME ZONE,
  status public.coding_session_status DEFAULT 'active' NOT NULL,

  -- Context
  current_branch TEXT,
  working_directory TEXT,

  -- Real-time sync
  last_heartbeat_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE public.coding_sessions IS 'Active Claude Code sessions for two-way mobile communication.';

ALTER TABLE public.coding_sessions OWNER TO postgres;

-- Indexes
CREATE INDEX idx_coding_sessions_user_id ON public.coding_sessions(user_id);
CREATE INDEX idx_coding_sessions_device_id ON public.coding_sessions(device_id);
CREATE INDEX idx_coding_sessions_repository_id ON public.coding_sessions(repository_id);
CREATE INDEX idx_coding_sessions_status ON public.coding_sessions(status);
CREATE INDEX idx_coding_sessions_last_heartbeat ON public.coding_sessions(last_heartbeat_at);
CREATE INDEX idx_coding_sessions_user_status ON public.coding_sessions(user_id, status);
CREATE INDEX idx_coding_sessions_device_status ON public.coding_sessions(device_id, status);

-- Enable Realtime for mobile push updates
ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.coding_sessions;

-- Enable RLS
ALTER TABLE public.coding_sessions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own sessions" ON public.coding_sessions
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can insert their own sessions" ON public.coding_sessions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update their own sessions" ON public.coding_sessions
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can delete their own sessions" ON public.coding_sessions
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));
