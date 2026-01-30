-- =============================================================================
-- PGTAP Tests: Marketing Table RLS Policies - Structure Tests
-- =============================================================================
-- Since PGTAP runs as postgres superuser (bypassing RLS), we test:
-- 1. Table structure and RLS enabled status
-- 2. Verify expected columns exist
--
-- Tables covered:
--   - marketing_author_profiles
--   - marketing_tags
--   - marketing_blog_posts
--   - marketing_feedback_boards
--   - marketing_feedback_threads
--   - marketing_feedback_comments
--   - marketing_feedback_thread_reactions
--   - marketing_feedback_comment_reactions
-- =============================================================================

BEGIN;

-- Create the tests schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS tests;

SELECT plan(22);

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

-- =============================================================================
-- MARKETING_AUTHOR_PROFILES TABLE TESTS
-- =============================================================================

-- Test 1: marketing_author_profiles table exists
SELECT has_table('public', 'marketing_author_profiles', 'marketing_author_profiles table exists');

-- Test 2: marketing_author_profiles has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_author_profiles'),
  'marketing_author_profiles: RLS is enabled'
);

-- =============================================================================
-- MARKETING_TAGS TABLE TESTS
-- =============================================================================

-- Test 3: marketing_tags table exists
SELECT has_table('public', 'marketing_tags', 'marketing_tags table exists');

-- Test 4: marketing_tags has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_tags'),
  'marketing_tags: RLS is enabled'
);

-- =============================================================================
-- MARKETING_BLOG_POSTS TABLE TESTS
-- =============================================================================

-- Test 5: marketing_blog_posts table exists
SELECT has_table('public', 'marketing_blog_posts', 'marketing_blog_posts table exists');

-- Test 6: marketing_blog_posts has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_blog_posts'),
  'marketing_blog_posts: RLS is enabled'
);

-- =============================================================================
-- MARKETING_FEEDBACK_BOARDS TABLE TESTS
-- =============================================================================

-- Test 7: marketing_feedback_boards table exists
SELECT has_table('public', 'marketing_feedback_boards', 'marketing_feedback_boards table exists');

-- Test 8: marketing_feedback_boards has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_feedback_boards'),
  'marketing_feedback_boards: RLS is enabled'
);

-- Test 9-12: marketing_feedback_boards has expected RLS policies
SELECT policy_cmd_is('public', 'marketing_feedback_boards', 'Public boards are viewable by everyone', 'select', 'marketing_feedback_boards: Public SELECT policy exists');
SELECT policy_cmd_is('public', 'marketing_feedback_boards', 'Only admins can insert boards', 'insert', 'marketing_feedback_boards: Admin INSERT policy exists');
SELECT policy_cmd_is('public', 'marketing_feedback_boards', 'Only admins can update boards', 'update', 'marketing_feedback_boards: Admin UPDATE policy exists');
SELECT policy_cmd_is('public', 'marketing_feedback_boards', 'Only admins can delete boards', 'delete', 'marketing_feedback_boards: Admin DELETE policy exists');

-- =============================================================================
-- MARKETING_FEEDBACK_THREADS TABLE TESTS
-- =============================================================================

-- Test 13: marketing_feedback_threads table exists
SELECT has_table('public', 'marketing_feedback_threads', 'marketing_feedback_threads table exists');

-- Test 14: marketing_feedback_threads has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_feedback_threads'),
  'marketing_feedback_threads: RLS is enabled'
);

-- Test 15-16: marketing_feedback_threads has expected columns
SELECT has_column('public', 'marketing_feedback_threads', 'user_id', 'marketing_feedback_threads has user_id column');
SELECT has_column('public', 'marketing_feedback_threads', 'is_publicly_visible', 'marketing_feedback_threads has is_publicly_visible column');

-- =============================================================================
-- MARKETING_FEEDBACK_COMMENTS TABLE TESTS
-- =============================================================================

-- Test 17: marketing_feedback_comments table exists
SELECT has_table('public', 'marketing_feedback_comments', 'marketing_feedback_comments table exists');

-- Test 18: marketing_feedback_comments has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_feedback_comments'),
  'marketing_feedback_comments: RLS is enabled'
);

-- =============================================================================
-- MARKETING_FEEDBACK_THREAD_REACTIONS TABLE TESTS
-- =============================================================================

-- Test 19: marketing_feedback_thread_reactions table exists
SELECT has_table('public', 'marketing_feedback_thread_reactions', 'marketing_feedback_thread_reactions table exists');

-- Test 20: marketing_feedback_thread_reactions has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_feedback_thread_reactions'),
  'marketing_feedback_thread_reactions: RLS is enabled'
);

-- =============================================================================
-- MARKETING_FEEDBACK_COMMENT_REACTIONS TABLE TESTS
-- =============================================================================

-- Test 21: marketing_feedback_comment_reactions table exists
SELECT has_table('public', 'marketing_feedback_comment_reactions', 'marketing_feedback_comment_reactions table exists');

-- Test 22: marketing_feedback_comment_reactions has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'marketing_feedback_comment_reactions'),
  'marketing_feedback_comment_reactions: RLS is enabled'
);

-- =============================================================================
-- Cleanup
-- =============================================================================
SELECT tests.clear_auth();

SELECT * FROM finish();
ROLLBACK;
