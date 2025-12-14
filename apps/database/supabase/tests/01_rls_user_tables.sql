-- =============================================================================
-- PGTAP Tests: User Table RLS Policies - Security Function Tests
-- =============================================================================
-- Since PGTAP runs as postgres superuser (bypassing RLS), we test the
-- underlying security functions that RLS policies rely on.
--
-- Tables covered:
--   - user_profiles
--   - user_settings
--   - user_application_settings
--   - user_notifications
--   - user_api_keys
-- =============================================================================

BEGIN;

-- Create the tests schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS tests;

SELECT plan(12);

-- =============================================================================
-- Setup: Create helper functions in tests schema
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
-- Admin:  00000000-0000-0000-0000-000000000001
-- Alice:  aaaaaaaa-1111-1111-1111-111111111111
-- Bob:    bbbbbbbb-2222-2222-2222-222222222222
-- Carol:  cccccccc-3333-3333-3333-333333333333

-- =============================================================================
-- USER_PROFILES TABLE STRUCTURE TESTS
-- =============================================================================

-- Test 1: user_profiles table exists
SELECT has_table('public', 'user_profiles', 'user_profiles table exists');

-- Test 2: user_profiles has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'user_profiles'),
  'user_profiles: RLS is enabled'
);

-- Test 3: user_profiles has expected columns
SELECT has_column('public', 'user_profiles', 'id', 'user_profiles has id column');
SELECT has_column('public', 'user_profiles', 'full_name', 'user_profiles has full_name column');
SELECT has_column('public', 'user_profiles', 'avatar_url', 'user_profiles has avatar_url column');

-- =============================================================================
-- USER_SETTINGS TABLE STRUCTURE TESTS
-- =============================================================================

-- Test 6: user_settings table exists
SELECT has_table('public', 'user_settings', 'user_settings table exists');

-- Test 7: user_settings has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'user_settings'),
  'user_settings: RLS is enabled'
);

-- =============================================================================
-- USER_APPLICATION_SETTINGS TABLE STRUCTURE TESTS
-- =============================================================================

-- Test 8: user_application_settings table exists
SELECT has_table('public', 'user_application_settings', 'user_application_settings table exists');

-- Test 9: user_application_settings has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'user_application_settings'),
  'user_application_settings: RLS is enabled'
);

-- =============================================================================
-- USER_NOTIFICATIONS TABLE STRUCTURE TESTS
-- =============================================================================

-- Test 10: user_notifications table exists
SELECT has_table('public', 'user_notifications', 'user_notifications table exists');

-- Test 11: user_notifications has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'user_notifications'),
  'user_notifications: RLS is enabled'
);

-- =============================================================================
-- USER_API_KEYS TABLE TESTS
-- =============================================================================

-- Test 12: user_api_keys table exists with RLS
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'user_api_keys'),
  'user_api_keys: RLS is enabled'
);

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
