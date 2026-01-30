-- =============================================================================
-- PGTAP Tests: Function Unit Tests
-- =============================================================================
-- Tests for public functions:
--   - is_application_admin(user_id)
--   - make_user_app_admin(user_id)
--   - remove_app_admin_privilege_for_user(user_id)
-- =============================================================================

BEGIN;

-- Create the tests schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS tests;

SELECT plan(7);

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
-- is_application_admin(user_id) TESTS
-- =============================================================================

-- Test 1: is_application_admin returns true for app admin
SELECT ok(
  is_application_admin('00000000-0000-0000-0000-000000000001'::uuid) = true,
  'is_application_admin: Returns true for app admin'
);

-- Test 2: is_application_admin returns false for regular user
SELECT ok(
  is_application_admin('aaaaaaaa-1111-1111-1111-111111111111'::uuid) = false,
  'is_application_admin: Returns false for regular user (Alice)'
);

-- Test 3: is_application_admin returns false for NULL
SELECT ok(
  is_application_admin(NULL::uuid) = false,
  'is_application_admin: Returns false for NULL user_id'
);

-- =============================================================================
-- make_user_app_admin(user_id) TESTS
-- =============================================================================

-- Test 4: make_user_app_admin grants admin role to a user
SELECT lives_ok(
  $$SELECT make_user_app_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid)$$,
  'make_user_app_admin: Successfully grants admin role'
);

-- Test 5: Verify the user is now an admin
SELECT ok(
  is_application_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid) = true,
  'make_user_app_admin: User is now an app admin after granting'
);

-- =============================================================================
-- remove_app_admin_privilege_for_user(user_id) TESTS
-- =============================================================================

-- Test 6: remove_app_admin_privilege_for_user revokes admin role
SELECT lives_ok(
  $$SELECT remove_app_admin_privilege_for_user('bbbbbbbb-2222-2222-2222-222222222222'::uuid)$$,
  'remove_app_admin_privilege_for_user: Successfully revokes admin role'
);

-- Test 7: Verify the user is no longer an admin
SELECT ok(
  is_application_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid) = false,
  'remove_app_admin_privilege_for_user: User is no longer an app admin'
);

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
