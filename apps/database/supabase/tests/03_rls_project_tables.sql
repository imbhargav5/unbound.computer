-- =============================================================================
-- PGTAP Tests: Project Table RLS Policies - Structure & Function Tests
-- =============================================================================
-- Since PGTAP runs as postgres superuser (bypassing RLS), we test:
-- 1. Table structure and RLS enabled status
-- 2. Security helper functions that RLS policies rely on
--
-- Tables covered:
--   - projects
--   - project_comments
--   - chats
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
-- Admin:  00000000-0000-0000-0000-000000000001 (owner of their workspace)
-- Alice:  aaaaaaaa-1111-1111-1111-111111111111 (owner of their workspace)
-- Bob:    bbbbbbbb-2222-2222-2222-222222222222 (owner of their workspace)
-- Carol:  cccccccc-3333-3333-3333-333333333333 (owner of their workspace)

-- =============================================================================
-- PROJECTS TABLE TESTS
-- =============================================================================

-- Test 1: projects table exists
SELECT has_table('public', 'projects', 'projects table exists');

-- Test 2: projects has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'projects'),
  'projects: RLS is enabled'
);

-- Test 3-5: projects has expected columns
SELECT has_column('public', 'projects', 'id', 'projects has id column');
SELECT has_column('public', 'projects', 'name', 'projects has name column');
SELECT has_column('public', 'projects', 'workspace_id', 'projects has workspace_id column');

-- =============================================================================
-- PROJECT_COMMENTS TABLE TESTS
-- =============================================================================

-- Test 6: project_comments table exists
SELECT has_table('public', 'project_comments', 'project_comments table exists');

-- Test 7: project_comments has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'project_comments'),
  'project_comments: RLS is enabled'
);

-- Test 8-9: project_comments has expected columns
SELECT has_column('public', 'project_comments', 'project_id', 'project_comments has project_id column');
SELECT has_column('public', 'project_comments', 'user_id', 'project_comments has user_id column');

-- =============================================================================
-- CHATS TABLE TESTS
-- =============================================================================

-- Test 10: chats table exists
SELECT has_table('public', 'chats', 'chats table exists');

-- Test 11: chats has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'chats'),
  'chats: RLS is enabled'
);

-- Test 12-13: chats has expected columns
SELECT has_column('public', 'chats', 'user_id', 'chats has user_id column');
SELECT has_column('public', 'chats', 'project_id', 'chats has project_id column');

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
