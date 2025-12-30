/*
 * REPOSITORIES TABLE
 *
 * Tracks git repositories registered by users on their devices.
 * Supports worktree detection and consolidation under parent repos.
 */

CREATE TABLE IF NOT EXISTS public.repositories (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,

  -- Git information
  name TEXT NOT NULL,
  local_path TEXT NOT NULL,
  remote_url TEXT,
  default_branch TEXT,

  -- Worktree relationship
  parent_repository_id UUID REFERENCES public.repositories(id) ON DELETE CASCADE,
  is_worktree BOOLEAN DEFAULT false NOT NULL,
  worktree_branch TEXT,

  -- Status and metadata
  status public.repository_status DEFAULT 'active' NOT NULL,
  last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

  -- Unique constraint: same path on same device
  UNIQUE(device_id, local_path)
);

COMMENT ON TABLE public.repositories IS 'Git repositories registered for remote access. Supports worktree consolidation.';

ALTER TABLE public.repositories OWNER TO postgres;

-- Indexes
CREATE INDEX idx_repositories_user_id ON public.repositories(user_id);
CREATE INDEX idx_repositories_device_id ON public.repositories(device_id);
CREATE INDEX idx_repositories_parent_repository_id ON public.repositories(parent_repository_id);
CREATE INDEX idx_repositories_remote_url ON public.repositories(remote_url);
CREATE INDEX idx_repositories_status ON public.repositories(status);
CREATE INDEX idx_repositories_is_worktree ON public.repositories(is_worktree);

-- Enable RLS
ALTER TABLE public.repositories ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own repositories" ON public.repositories
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can insert their own repositories" ON public.repositories
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update their own repositories" ON public.repositories
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can delete their own repositories" ON public.repositories
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));
