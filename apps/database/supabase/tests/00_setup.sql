-- =============================================================================
-- PGTAP Test Setup - Helper Functions and Test Data References
-- =============================================================================
-- This file sets up the testing environment for PGTAP tests.
-- Run this before all other test files.
-- =============================================================================

BEGIN;

-- Create the tests schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS tests;

-- Plan: Just setup, no actual tests in this file
SELECT plan(1);

-- =============================================================================
-- TEST USER UUIDs (from seed.sql)
-- =============================================================================
-- These constants reference users created by the seed data:
--   Admin:  00000000-0000-0000-0000-000000000001 (testadmin@usenextbase.com)
--   Alice:  aaaaaaaa-1111-1111-1111-111111111111 (alice@example.com)
--   Bob:    bbbbbbbb-2222-2222-2222-222222222222 (bob@example.com)
--   Carol:  cccccccc-3333-3333-3333-333333333333 (carol@example.com)

-- =============================================================================
-- HELPER FUNCTION: Set authenticated user context for RLS testing
-- =============================================================================
-- This simulates an authenticated user by setting the JWT claims that
-- Supabase uses for RLS policies.
-- NOTE: We only set JWT claims, not the database role. The tests run as
-- postgres superuser but RLS policies check auth.uid() which reads from
-- request.jwt.claims.
CREATE OR REPLACE FUNCTION tests.set_auth_user(p_user_id uuid)
RETURNS void AS $$
BEGIN
  -- Set the JWT claims that auth.uid() reads from
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', p_user_id::text,
    'role', 'authenticated',
    'aud', 'authenticated'
  )::text, true);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- HELPER FUNCTION: Set anonymous user context
-- =============================================================================
CREATE OR REPLACE FUNCTION tests.set_anon_user()
RETURNS void AS $$
BEGIN
  -- Clear JWT claims to simulate anonymous user
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- HELPER FUNCTION: Clear authentication context
-- =============================================================================
CREATE OR REPLACE FUNCTION tests.clear_auth()
RETURNS void AS $$
BEGIN
  -- Reset JWT claims
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Verify setup was successful
-- =============================================================================
SELECT ok(
  (SELECT COUNT(*) FROM information_schema.routines
   WHERE routine_schema = 'tests' AND routine_name = 'set_auth_user') = 1,
  'Test helper function set_auth_user exists'
);

SELECT * FROM finish();
ROLLBACK;
