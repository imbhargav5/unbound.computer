/*
 * Workspace Performance Optimizations Migration
 * 
 * This migration includes the following optimizations:
 * 1. Partial index on workspace_invitations for active invitations lookup
 * 2. Recreate is_workspace_member and is_workspace_admin functions with SQL language + STABLE modifier
 * 3. Composite index on workspace_members(workspace_member_id, workspace_id)
 * 4. Composite index on projects(workspace_id, created_at DESC) for paginated project listing
 * 5. Composite index on user_notifications(user_id, created_at DESC) for paginated notification listing
 */

-- =============================================================================
-- 1. Partial Index for Active Invitations
-- =============================================================================
-- Partial index for querying active invitations by invitee_user_id
-- Optimizes: SELECT ... FROM workspace_invitations WHERE invitee_user_id = ? AND status = 'active'
CREATE INDEX idx_workspace_invitations_active_invitee 
ON public.workspace_invitations(invitee_user_id) 
WHERE status = 'active';

-- =============================================================================
-- 2. Recreate is_workspace_member with SQL + STABLE
-- =============================================================================
-- Recreate is_workspace_member with SQL language and STABLE modifier for better performance
CREATE OR REPLACE FUNCTION public.is_workspace_member(user_id uuid, workspace_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM workspace_members
    WHERE workspace_member_id = $1
      AND workspace_id = $2
  );
$$;

ALTER FUNCTION public.is_workspace_member(user_id uuid, workspace_id uuid) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.is_workspace_member(user_id uuid, workspace_id uuid) FROM public;
REVOKE ALL ON FUNCTION public.is_workspace_member(user_id uuid, workspace_id uuid) FROM anon;

GRANT EXECUTE ON FUNCTION public.is_workspace_member(user_id uuid, workspace_id uuid) TO service_role;

-- =============================================================================
-- 3. Recreate is_workspace_admin with SQL + STABLE
-- =============================================================================
-- Recreate is_workspace_admin with SQL language and STABLE modifier for better performance
CREATE OR REPLACE FUNCTION public.is_workspace_admin(user_id uuid, workspace_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM workspace_members
    WHERE workspace_member_id = $1
      AND workspace_id = $2
      AND (workspace_member_role = 'admin' OR workspace_member_role = 'owner')
  );
$$;

ALTER FUNCTION public.is_workspace_admin(user_id uuid, workspace_id uuid) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.is_workspace_admin(user_id uuid, workspace_id uuid) FROM public;
REVOKE ALL ON FUNCTION public.is_workspace_admin(user_id uuid, workspace_id uuid) FROM anon;

GRANT EXECUTE ON FUNCTION public.is_workspace_admin(user_id uuid, workspace_id uuid) TO service_role;

-- =============================================================================
-- 4. Composite Index on workspace_members
-- =============================================================================
-- Composite index for workspace membership lookups
-- Optimizes is_workspace_member and is_workspace_admin function queries
CREATE INDEX idx_workspace_members_member_workspace 
ON public.workspace_members(workspace_member_id, workspace_id);

-- =============================================================================
-- 5. Composite Index on projects for Paginated Listing
-- =============================================================================
-- Composite index for paginated project listing by workspace
-- Optimizes: SELECT * FROM projects WHERE workspace_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?
-- Column order: workspace_id first (equality), created_at DESC second (ordering)
CREATE INDEX idx_projects_workspace_created 
ON public.projects(workspace_id, created_at DESC);

-- =============================================================================
-- 6. Composite Index on user_notifications for Paginated Listing
-- =============================================================================
-- Composite index for paginated notification listing by user
-- Optimizes: SELECT * FROM user_notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?
CREATE INDEX idx_user_notifications_user_created 
ON public.user_notifications(user_id, created_at DESC);

-- ==================== ROLLBACK ====================
-- Uncomment the following statements to rollback this migration
--
-- DROP INDEX IF EXISTS public.idx_workspace_invitations_active_invitee;
-- DROP INDEX IF EXISTS public.idx_workspace_members_member_workspace;
-- DROP INDEX IF EXISTS public.idx_projects_workspace_created;
-- DROP INDEX IF EXISTS public.idx_user_notifications_user_created;
--
-- Note: Functions are replaced in-place, rollback would require restoring original plpgsql versions
-- ==================== END ROLLBACK ====================
