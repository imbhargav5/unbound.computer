-- =============================================================================
-- PGTAP Tests: Workspace Table RLS Policies - Structure & Function Tests
-- =============================================================================
-- Since PGTAP runs as postgres superuser (bypassing RLS), we test:
-- 1. Table structure and RLS enabled status
-- 2. Security helper functions that RLS policies rely on
--
-- Tables covered:
--   - workspaces
--   - workspace_settings
--   - workspace_admin_settings
--   - workspace_application_settings
--   - workspace_members
--   - workspace_invitations
--   - workspace_credits
--   - workspace_credits_logs
-- =============================================================================

BEGIN;

-- Create the tests schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS tests;

SELECT plan(18);

-- =============================================================================
-- Setup: Create helper functions
-- =============================================================================

CREATE OR REPLACE FUNCTION tests.set_auth_user(p_user_id uuid)
RETURNS void AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', p_user_id::text,
    'role', 'authenticated',
    'aud', 'authenticated'
  )::text, true);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION tests.clear_auth()
RETURNS void AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$ LANGUAGE plpgsql;

-- Test user UUIDs from seed data
-- Admin:  00000000-0000-0000-0000-000000000001 (owner of their workspace)
-- Alice:  aaaaaaaa-1111-1111-1111-111111111111 (owner of their workspace)
-- Bob:    bbbbbbbb-2222-2222-2222-222222222222 (owner of their workspace)
-- Carol:  cccccccc-3333-3333-3333-333333333333 (owner of their workspace)

-- =============================================================================
-- WORKSPACES TABLE TESTS
-- =============================================================================

-- Test 1: workspaces table exists
SELECT has_table('public', 'workspaces', 'workspaces table exists');

-- Test 2: workspaces has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspaces'),
  'workspaces: RLS is enabled'
);

-- Test 3: workspaces has expected columns
SELECT has_column('public', 'workspaces', 'id', 'workspaces has id column');
SELECT has_column('public', 'workspaces', 'slug', 'workspaces has slug column');
SELECT has_column('public', 'workspaces', 'name', 'workspaces has name column');

-- =============================================================================
-- WORKSPACE_SETTINGS TABLE TESTS
-- =============================================================================

-- Test 6: workspace_settings has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspace_settings'),
  'workspace_settings: RLS is enabled'
);

-- =============================================================================
-- WORKSPACE_ADMIN_SETTINGS TABLE TESTS
-- =============================================================================

-- Test 7: workspace_admin_settings has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspace_admin_settings'),
  'workspace_admin_settings: RLS is enabled'
);

-- =============================================================================
-- WORKSPACE_APPLICATION_SETTINGS TABLE TESTS
-- =============================================================================

-- Test 8: workspace_application_settings has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspace_application_settings'),
  'workspace_application_settings: RLS is enabled'
);

-- =============================================================================
-- WORKSPACE_MEMBERS TABLE TESTS
-- =============================================================================

-- Test 9: workspace_members has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspace_members'),
  'workspace_members: RLS is enabled'
);

-- Test 10: workspace_members has expected columns
SELECT has_column('public', 'workspace_members', 'workspace_member_role', 'workspace_members has role column');

-- =============================================================================
-- WORKSPACE_INVITATIONS TABLE TESTS
-- =============================================================================

-- Test 11: workspace_invitations has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspace_invitations'),
  'workspace_invitations: RLS is enabled'
);

-- =============================================================================
-- WORKSPACE_CREDITS TABLE TESTS
-- =============================================================================

-- Test 12: workspace_credits has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspace_credits'),
  'workspace_credits: RLS is enabled'
);

-- =============================================================================
-- WORKSPACE_CREDITS_LOGS TABLE TESTS
-- =============================================================================

-- Test 13: workspace_credits_logs has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'workspace_credits_logs'),
  'workspace_credits_logs: RLS is enabled'
);

-- =============================================================================
-- SECURITY FUNCTION TESTS - is_workspace_member
-- Note: is_workspace_member(user_id, workspace_id) - user_id comes first
-- =============================================================================

-- Test 14: is_workspace_member returns true for workspace owner
SELECT ok(
  is_workspace_member(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = true,
  'is_workspace_member: Returns true for Alice in her own workspace'
);

-- Test 15: is_workspace_member returns false for non-member
SELECT ok(
  is_workspace_member(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-bbbbbbbb-2222-2222-2222-222222222222')
  ) = false,
  'is_workspace_member: Returns false for Alice in Bob''s workspace'
);

-- =============================================================================
-- SECURITY FUNCTION TESTS - is_workspace_admin
-- =============================================================================

-- Test 16: is_workspace_admin returns true for workspace owner
SELECT ok(
  is_workspace_admin(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = true,
  'is_workspace_admin: Returns true for workspace owner (Alice)'
);

-- Test 17: is_workspace_admin returns false for non-member
SELECT ok(
  is_workspace_admin(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-bbbbbbbb-2222-2222-2222-222222222222')
  ) = false,
  'is_workspace_admin: Returns false for non-member (Alice in Bob''s workspace)'
);

-- =============================================================================
-- DATA VERIFICATION
-- =============================================================================

-- Test 18: Verify seed data created workspaces for all users
SELECT ok(
  (SELECT COUNT(*) FROM workspaces WHERE slug LIKE 'personal-%') >= 4,
  'Seed data: At least 4 personal workspaces exist'
);

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
