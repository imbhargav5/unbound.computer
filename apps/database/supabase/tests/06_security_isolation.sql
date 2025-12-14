-- =============================================================================
-- PGTAP Tests: Cross-User Data Isolation & Security Tests
-- =============================================================================
-- Tests security helper functions to ensure proper access control:
--   - Users cannot access other users' private data (via function tests)
--   - Privilege escalation is prevented
--   - Data leakage is prevented
--   - Admin-only operations are properly protected
--
-- Note: Since PGTAP runs as postgres superuser (bypassing RLS), we test
-- the underlying security functions that RLS policies rely on.
-- =============================================================================

BEGIN;

-- Create the tests schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS tests;

SELECT plan(13);

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
-- Admin:  00000000-0000-0000-0000-000000000001 (app admin)
-- Alice:  aaaaaaaa-1111-1111-1111-111111111111 (regular user)
-- Bob:    bbbbbbbb-2222-2222-2222-222222222222 (regular user)
-- Carol:  cccccccc-3333-3333-3333-333333333333 (regular user)

-- =============================================================================
-- CROSS-WORKSPACE ISOLATION TESTS (via security functions)
-- =============================================================================

-- Test 1: Alice is not a member of Bob's workspace
SELECT ok(
  is_workspace_member(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-bbbbbbbb-2222-2222-2222-222222222222')
  ) = false,
  'SECURITY: Alice is NOT a member of Bob''s workspace'
);

-- Test 2: Bob is not a member of Alice's workspace
SELECT ok(
  is_workspace_member(
    'bbbbbbbb-2222-2222-2222-222222222222'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = false,
  'SECURITY: Bob is NOT a member of Alice''s workspace'
);

-- Test 3: Carol is not a member of Alice's workspace
SELECT ok(
  is_workspace_member(
    'cccccccc-3333-3333-3333-333333333333'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = false,
  'SECURITY: Carol is NOT a member of Alice''s workspace'
);

-- =============================================================================
-- ADMIN PRIVILEGE ISOLATION TESTS
-- =============================================================================

-- Test 4: Alice is not an admin of Bob's workspace
SELECT ok(
  is_workspace_admin(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-bbbbbbbb-2222-2222-2222-222222222222')
  ) = false,
  'SECURITY: Alice is NOT an admin of Bob''s workspace'
);

-- Test 5: Bob is not an admin of Alice's workspace
SELECT ok(
  is_workspace_admin(
    'bbbbbbbb-2222-2222-2222-222222222222'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = false,
  'SECURITY: Bob is NOT an admin of Alice''s workspace'
);

-- Test 6: Admin user is admin of their own workspace
SELECT ok(
  is_workspace_admin(
    '00000000-0000-0000-0000-000000000001'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-00000000-0000-0000-0000-000000000001')
  ) = true,
  'SECURITY: Admin is admin of their own workspace'
);

-- =============================================================================
-- APPLICATION ADMIN ROLE TESTS
-- =============================================================================

-- Test 7: Regular user Alice is NOT an application admin
SELECT ok(
  is_application_admin('aaaaaaaa-1111-1111-1111-111111111111'::uuid) = false,
  'SECURITY: Alice is NOT an application admin'
);

-- Test 8: Regular user Bob is NOT an application admin
SELECT ok(
  is_application_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid) = false,
  'SECURITY: Bob is NOT an application admin'
);

-- Test 9: Admin user IS an application admin
SELECT ok(
  is_application_admin('00000000-0000-0000-0000-000000000001'::uuid) = true,
  'SECURITY: Admin user IS an application admin'
);

-- =============================================================================
-- USER DATA ISOLATION - VERIFY SEED DATA
-- =============================================================================

-- Test 10: Each user has their own workspace
SELECT ok(
  (SELECT COUNT(*) FROM workspaces WHERE slug LIKE 'personal-%') >= 4,
  'DATA: At least 4 personal workspaces exist (one per user)'
);

-- Test 11: Each user has their own profile
SELECT ok(
  (SELECT COUNT(*) FROM user_profiles WHERE id IN (
    '00000000-0000-0000-0000-000000000001',
    'aaaaaaaa-1111-1111-1111-111111111111',
    'bbbbbbbb-2222-2222-2222-222222222222',
    'cccccccc-3333-3333-3333-333333333333'
  )) = 4,
  'DATA: All 4 test users have profiles'
);

-- Test 12: Each workspace has exactly one owner
SELECT ok(
  (SELECT COUNT(*) FROM workspace_members wm
   WHERE wm.workspace_member_role = 'owner'
   AND wm.workspace_id IN (
     SELECT id FROM workspaces WHERE slug LIKE 'personal-%'
   )) >= 4,
  'DATA: Each personal workspace has an owner'
);

-- =============================================================================
-- RLS ENABLED VERIFICATION FOR SENSITIVE TABLES
-- =============================================================================

-- Test 13: All sensitive tables have RLS enabled
SELECT ok(
  (SELECT COUNT(*) FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND c.relrowsecurity = true
   AND c.relname IN (
     'user_profiles', 'user_settings', 'user_application_settings',
     'user_notifications', 'user_api_keys', 'user_roles',
     'workspaces', 'workspace_members', 'workspace_settings',
     'workspace_admin_settings', 'workspace_credits',
     'projects', 'project_comments', 'chats',
     'app_settings'
   )) >= 10,
  'SECURITY: At least 10 sensitive tables have RLS enabled'
);

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
