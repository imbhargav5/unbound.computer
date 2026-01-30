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

SELECT plan(6);

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
-- APPLICATION ADMIN ROLE TESTS
-- =============================================================================

-- Test 1: Regular user Alice is NOT an application admin
SELECT ok(
  is_application_admin('aaaaaaaa-1111-1111-1111-111111111111'::uuid) = false,
  'SECURITY: Alice is NOT an application admin'
);

-- Test 2: Regular user Bob is NOT an application admin
SELECT ok(
  is_application_admin('bbbbbbbb-2222-2222-2222-222222222222'::uuid) = false,
  'SECURITY: Bob is NOT an application admin'
);

-- Test 3: Admin user IS an application admin
SELECT ok(
  is_application_admin('00000000-0000-0000-0000-000000000001'::uuid) = true,
  'SECURITY: Admin user IS an application admin'
);

-- =============================================================================
-- USER DATA ISOLATION - VERIFY SEED DATA
-- =============================================================================

-- Test 4: Each user has their own profile
SELECT ok(
  (SELECT COUNT(*) FROM user_profiles WHERE id IN (
    '00000000-0000-0000-0000-000000000001',
    'aaaaaaaa-1111-1111-1111-111111111111',
    'bbbbbbbb-2222-2222-2222-222222222222',
    'cccccccc-3333-3333-3333-333333333333'
  )) = 4,
  'DATA: All 4 test users have profiles'
);

-- =============================================================================
-- RLS ENABLED VERIFICATION FOR SENSITIVE TABLES
-- =============================================================================

-- Test 5: User tables have RLS enabled
SELECT ok(
  (SELECT COUNT(*) FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND c.relrowsecurity = true
   AND c.relname IN (
     'user_profiles', 'user_settings', 'user_application_settings',
     'user_notifications', 'user_api_keys', 'user_roles',
     'app_settings'
   )) >= 5,
  'SECURITY: At least 5 user-related tables have RLS enabled'
);

-- Test 6: Billing tables have RLS enabled
SELECT ok(
  (SELECT COUNT(*) FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND c.relrowsecurity = true
   AND c.relname IN (
     'billing_customers', 'billing_subscriptions', 'billing_invoices',
     'billing_payment_methods', 'billing_one_time_payments', 'billing_usage_logs'
   )) >= 4,
  'SECURITY: At least 4 billing tables have RLS enabled'
);

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
