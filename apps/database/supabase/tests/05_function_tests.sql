-- =============================================================================
-- PGTAP Tests: Function Unit Tests
-- =============================================================================
-- Tests for public functions:
--   - is_workspace_member(user_id, workspace_id)
--   - is_workspace_admin(user_id, workspace_id)
--   - is_application_admin(user_id)
--   - make_user_app_admin(user_id)
--   - remove_app_admin_privilege_for_user(user_id)
--   - get_project_workspace_uuid(project_id)
-- =============================================================================

BEGIN;

-- Create the tests schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS tests;

SELECT plan(16);

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
-- Alice:  aaaaaaaa-1111-1111-1111-111111111111 (owner of their workspace)
-- Bob:    bbbbbbbb-2222-2222-2222-222222222222 (owner of their workspace)
-- Carol:  cccccccc-3333-3333-3333-333333333333 (owner of their workspace)

-- =============================================================================
-- is_workspace_member(user_id, workspace_id) TESTS
-- Note: Parameter order is (user_id, workspace_id)
-- =============================================================================

-- Test 1: is_workspace_member returns true for workspace owner
SELECT ok(
  is_workspace_member(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = true,
  'is_workspace_member: Returns true for workspace owner (Alice)'
);

-- Test 2: is_workspace_member returns false for non-member
SELECT ok(
  is_workspace_member(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-bbbbbbbb-2222-2222-2222-222222222222')
  ) = false,
  'is_workspace_member: Returns false for non-member (Alice not in Bob''s workspace)'
);

-- Test 3: is_workspace_member handles NULL user_id
SELECT ok(
  is_workspace_member(
    NULL::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = false,
  'is_workspace_member: Returns false for NULL user_id'
);

-- Test 4: is_workspace_member handles NULL workspace_id
SELECT ok(
  is_workspace_member(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    NULL::uuid
  ) = false,
  'is_workspace_member: Returns false for NULL workspace_id'
);

-- =============================================================================
-- is_workspace_admin(user_id, workspace_id) TESTS
-- =============================================================================

-- Test 5: is_workspace_admin returns true for workspace owner
SELECT ok(
  is_workspace_admin(
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = true,
  'is_workspace_admin: Returns true for workspace owner (Alice)'
);

-- Test 6: is_workspace_admin returns false for non-admin member
-- First add Bob as a regular member to Alice's workspace
INSERT INTO workspace_members (workspace_id, workspace_member_id, workspace_member_role)
SELECT w.id, 'bbbbbbbb-2222-2222-2222-222222222222', 'member'
FROM workspaces w WHERE w.slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111';

SELECT ok(
  is_workspace_admin(
    'bbbbbbbb-2222-2222-2222-222222222222'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = false,
  'is_workspace_admin: Returns false for regular member (Bob as member in Alice''s workspace)'
);

-- Test 7: is_workspace_admin returns false for non-member
SELECT ok(
  is_workspace_admin(
    'cccccccc-3333-3333-3333-333333333333'::uuid,
    (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
  ) = false,
  'is_workspace_admin: Returns false for non-member (Carol)'
);

-- =============================================================================
-- is_application_admin(user_id) TESTS
-- =============================================================================

-- Test 8: is_application_admin returns true for app admin
SELECT ok(
  is_application_admin('00000000-0000-0000-0000-000000000001'::uuid) = true,
  'is_application_admin: Returns true for app admin'
);

-- Test 9: is_application_admin returns false for regular user
SELECT ok(
  is_application_admin('aaaaaaaa-1111-1111-1111-111111111111'::uuid) = false,
  'is_application_admin: Returns false for regular user (Alice)'
);

-- Test 10: is_application_admin returns false for NULL
SELECT ok(
  is_application_admin(NULL::uuid) = false,
  'is_application_admin: Returns false for NULL user_id'
);

-- =============================================================================
-- make_user_app_admin(user_id) TESTS
-- =============================================================================

-- Test 11: make_user_app_admin grants admin role to a user
SELECT lives_ok(
  $$SELECT make_user_app_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid)$$,
  'make_user_app_admin: Successfully grants admin role'
);

-- Test 12: Verify the user is now an admin
SELECT ok(
  is_application_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid) = true,
  'make_user_app_admin: User is now an app admin after granting'
);

-- =============================================================================
-- remove_app_admin_privilege_for_user(user_id) TESTS
-- =============================================================================

-- Test 13: remove_app_admin_privilege_for_user revokes admin role
SELECT lives_ok(
  $$SELECT remove_app_admin_privilege_for_user('bbbbbbbb-2222-2222-2222-222222222222'::uuid)$$,
  'remove_app_admin_privilege_for_user: Successfully revokes admin role'
);

-- Test 14: Verify the user is no longer an admin
SELECT ok(
  is_application_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid) = false,
  'remove_app_admin_privilege_for_user: User is no longer an app admin'
);

-- =============================================================================
-- get_project_workspace_uuid(project_id) TESTS
-- =============================================================================

-- Test 15: get_project_workspace_uuid returns correct workspace ID
SELECT ok(
  get_project_workspace_uuid(
    (SELECT id FROM projects
     WHERE workspace_id = (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111')
     LIMIT 1)
  ) = (SELECT id FROM workspaces WHERE slug = 'personal-aaaaaaaa-1111-1111-1111-111111111111'),
  'get_project_workspace_uuid: Returns correct workspace ID for project'
);

-- Test 16: get_project_workspace_uuid returns NULL for invalid project
SELECT ok(
  get_project_workspace_uuid('00000000-0000-0000-0000-000000000000'::uuid) IS NULL,
  'get_project_workspace_uuid: Returns NULL for non-existent project'
);

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
