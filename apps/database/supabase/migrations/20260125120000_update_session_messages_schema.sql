


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."app_role" AS ENUM (
    'admin'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";


CREATE TYPE "public"."coding_session_status" AS ENUM (
    'active',
    'paused',
    'ended'
);


ALTER TYPE "public"."coding_session_status" OWNER TO "postgres";


CREATE TYPE "public"."device_role" AS ENUM (
    'trust_root',
    'trusted_executor',
    'temporary_viewer'
);


ALTER TYPE "public"."device_role" OWNER TO "postgres";


CREATE TYPE "public"."device_type" AS ENUM (
    'mac-desktop',
    'win-desktop',
    'linux-desktop',
    'ios-tablet',
    'ios-phone',
    'android-tablet',
    'android-phone',
    'web-browser'
);


ALTER TYPE "public"."device_type" OWNER TO "postgres";


COMMENT ON TYPE "public"."device_type" IS 'Device types for registered devices: mac-desktop, win-desktop, linux-desktop, ios-tablet, ios-phone, android-tablet, android-phone, web-browser';



CREATE TYPE "public"."marketing_blog_post_status" AS ENUM (
    'draft',
    'published'
);


ALTER TYPE "public"."marketing_blog_post_status" OWNER TO "postgres";


CREATE TYPE "public"."marketing_changelog_status" AS ENUM (
    'draft',
    'published'
);


ALTER TYPE "public"."marketing_changelog_status" OWNER TO "postgres";


CREATE TYPE "public"."marketing_feedback_moderator_hold_category" AS ENUM (
    'spam',
    'off_topic',
    'inappropriate',
    'other'
);


ALTER TYPE "public"."marketing_feedback_moderator_hold_category" OWNER TO "postgres";


CREATE TYPE "public"."marketing_feedback_reaction_type" AS ENUM (
    'like',
    'heart',
    'celebrate',
    'upvote'
);


ALTER TYPE "public"."marketing_feedback_reaction_type" OWNER TO "postgres";


CREATE TYPE "public"."marketing_feedback_thread_priority" AS ENUM (
    'low',
    'medium',
    'high'
);


ALTER TYPE "public"."marketing_feedback_thread_priority" OWNER TO "postgres";


CREATE TYPE "public"."marketing_feedback_thread_status" AS ENUM (
    'open',
    'under_review',
    'planned',
    'closed',
    'in_progress',
    'completed',
    'moderator_hold'
);


ALTER TYPE "public"."marketing_feedback_thread_status" OWNER TO "postgres";


CREATE TYPE "public"."marketing_feedback_thread_type" AS ENUM (
    'bug',
    'feature_request',
    'general'
);


ALTER TYPE "public"."marketing_feedback_thread_type" OWNER TO "postgres";


CREATE TYPE "public"."organization_joining_status" AS ENUM (
    'invited',
    'joinied',
    'declined_invitation',
    'joined'
);


ALTER TYPE "public"."organization_joining_status" OWNER TO "postgres";


CREATE TYPE "public"."organization_member_role" AS ENUM (
    'owner',
    'admin',
    'member',
    'readonly'
);


ALTER TYPE "public"."organization_member_role" OWNER TO "postgres";


CREATE TYPE "public"."pairing_token_status" AS ENUM (
    'pending',
    'approved',
    'completed',
    'expired',
    'cancelled'
);


ALTER TYPE "public"."pairing_token_status" OWNER TO "postgres";


CREATE TYPE "public"."pricing_plan_interval" AS ENUM (
    'day',
    'week',
    'month',
    'year'
);


ALTER TYPE "public"."pricing_plan_interval" OWNER TO "postgres";


CREATE TYPE "public"."pricing_type" AS ENUM (
    'one_time',
    'recurring'
);


ALTER TYPE "public"."pricing_type" OWNER TO "postgres";


CREATE TYPE "public"."project_team_member_role" AS ENUM (
    'admin',
    'member',
    'readonly'
);


ALTER TYPE "public"."project_team_member_role" OWNER TO "postgres";


CREATE TYPE "public"."repository_status" AS ENUM (
    'active',
    'archived'
);


ALTER TYPE "public"."repository_status" OWNER TO "postgres";


CREATE TYPE "public"."subscription_status" AS ENUM (
    'trialing',
    'active',
    'canceled',
    'incomplete',
    'incomplete_expired',
    'past_due',
    'unpaid',
    'paused'
);


ALTER TYPE "public"."subscription_status" OWNER TO "postgres";


CREATE TYPE "public"."trust_relationship_status" AS ENUM (
    'pending',
    'active',
    'revoked',
    'expired'
);


ALTER TYPE "public"."trust_relationship_status" OWNER TO "postgres";


CREATE TYPE "public"."web_session_permission" AS ENUM (
    'view_only',
    'interact',
    'full_control'
);


ALTER TYPE "public"."web_session_permission" OWNER TO "postgres";


CREATE TYPE "public"."web_session_status" AS ENUM (
    'pending',
    'active',
    'expired',
    'revoked'
);


ALTER TYPE "public"."web_session_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_admin_get_projects_created_per_month"() RETURNS TABLE("month" "date", "number_of_projects" integer)
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'service_role',
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
CREATE TEMPORARY TABLE temp_result (MONTH DATE, number_of_projects INTEGER) ON COMMIT DROP;

  WITH date_series AS (
  SELECT DATE_TRUNC('MONTH', dd)::DATE AS MONTH
  FROM generate_series(
      DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '1 YEAR'),
      DATE_TRUNC('MONTH', CURRENT_DATE),
      '1 MONTH'::INTERVAL
    ) dd
),
project_counts AS (
  SELECT DATE_TRUNC('MONTH', created_at)::DATE AS MONTH,
    COUNT(*) AS project_count
  FROM public.projects
  WHERE created_at >= CURRENT_DATE - INTERVAL '1 YEAR'
  GROUP BY MONTH
)
INSERT INTO temp_result
SELECT date_series.month,
  COALESCE(project_counts.project_count, 0)
FROM date_series
  LEFT JOIN project_counts ON date_series.month = project_counts.month
ORDER BY date_series.month;

  RETURN QUERY
SELECT *
FROM temp_result;
END;
$$;


ALTER FUNCTION "public"."app_admin_get_projects_created_per_month"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_admin_get_recent_30_day_signin_count"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE signin_count INTEGER;
BEGIN IF CURRENT_ROLE NOT IN (
  'service_role',
  'supabase_admin',
  'dashboard_user',
  'postgres'
) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
SELECT COUNT(*) INTO signin_count
FROM auth.users
WHERE last_sign_in_at >= CURRENT_DATE - INTERVAL '30 DAYS';

RETURN signin_count;
END;
$$;


ALTER FUNCTION "public"."app_admin_get_recent_30_day_signin_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_admin_get_total_organization_count"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE org_count INTEGER;
BEGIN IF CURRENT_ROLE NOT IN (
  'service_role',
  'supabase_admin',
  'dashboard_user',
  'postgres'
) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
SELECT COUNT(*) INTO org_count
FROM public.organizations;
RETURN org_count;
END;
$$;


ALTER FUNCTION "public"."app_admin_get_total_organization_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_admin_get_total_project_count"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE proj_count INTEGER;
BEGIN IF CURRENT_ROLE NOT IN (
  'service_role',
  'supabase_admin',
  'dashboard_user',
  'postgres'
) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
SELECT COUNT(*) INTO proj_count
FROM public.projects;
RETURN proj_count;
END;
$$;


ALTER FUNCTION "public"."app_admin_get_total_project_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_admin_get_total_user_count"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE user_count INTEGER;
BEGIN IF CURRENT_ROLE NOT IN (
  'service_role',
  'supabase_admin',
  'dashboard_user',
  'postgres'
) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
SELECT COUNT(*) INTO user_count
FROM public.user_profiles;
RETURN user_count;
END;
$$;


ALTER FUNCTION "public"."app_admin_get_total_user_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_admin_get_user_id_by_email"("emailarg" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_user_id uuid;
BEGIN IF CURRENT_ROLE NOT IN (
  'service_role',
  'supabase_admin',
  'dashboard_user',
  'postgres'
) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;

SELECT id INTO v_user_id
FROM auth.users
WHERE LOWER(email) = LOWER(emailArg);

  RETURN v_user_id;
END;
$$;


ALTER FUNCTION "public"."app_admin_get_user_id_by_email"("emailarg" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_admin_get_users_created_per_month"() RETURNS TABLE("month" "date", "number_of_users" integer)
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'service_role',
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
CREATE TEMPORARY TABLE temp_result (MONTH DATE, number_of_users INTEGER) ON COMMIT DROP;

  WITH date_series AS (
  SELECT DATE_TRUNC('MONTH', dd)::DATE AS MONTH
  FROM generate_series(
      DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '1 YEAR'),
      DATE_TRUNC('MONTH', CURRENT_DATE),
      '1 MONTH'::INTERVAL
    ) dd
),
user_counts AS (
  SELECT DATE_TRUNC('MONTH', created_at)::DATE AS MONTH,
    COUNT(*) AS user_count
  FROM public.user_profiles
  WHERE created_at >= CURRENT_DATE - INTERVAL '1 YEAR'
  GROUP BY MONTH
)
INSERT INTO temp_result
SELECT date_series.month,
  COALESCE(user_counts.user_count, 0)
FROM date_series
  LEFT JOIN user_counts ON date_series.month = user_counts.month
ORDER BY date_series.month;

  RETURN QUERY
SELECT *
FROM temp_result;
END;
$$;


ALTER FUNCTION "public"."app_admin_get_users_created_per_month"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."authorize_web_session"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_session_user_id UUID;
  v_session_status public.web_session_status;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();

  -- Verify the session exists and is pending
  SELECT user_id, status INTO v_session_user_id, v_session_status
  FROM public.web_sessions
  WHERE id = p_session_id;

  IF v_session_user_id IS NULL THEN
    RAISE EXCEPTION 'Web session not found';
  END IF;

  IF v_session_user_id != v_user_id THEN
    RAISE EXCEPTION 'Not authorized to authorize this session';
  END IF;

  IF v_session_status != 'pending' THEN
    RAISE EXCEPTION 'Session is not in pending state';
  END IF;

  -- Verify the device belongs to the user
  IF NOT EXISTS (
    SELECT 1 FROM public.devices
    WHERE id = p_device_id AND user_id = v_user_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Device not found or not active';
  END IF;

  -- Authorize the session
  UPDATE public.web_sessions
  SET
    status = 'active',
    authorizing_device_id = p_device_id,
    encrypted_session_key = p_encrypted_session_key,
    responder_public_key = p_responder_public_key,
    authorized_at = NOW(),
    expires_at = NOW() + INTERVAL '24 hours',  -- Extend to 24 hours after authorization
    last_activity_at = NOW()
  WHERE id = p_session_id;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."authorize_web_session"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."authorize_web_session"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text") IS 'Authorizes a pending web session from a trusted device.';



CREATE OR REPLACE FUNCTION "public"."authorize_web_session_v2"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text", "p_permission" "public"."web_session_permission" DEFAULT 'view_only'::"public"."web_session_permission", "p_session_ttl_seconds" integer DEFAULT 86400, "p_max_idle_seconds" integer DEFAULT 1800) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id UUID;
  v_session_user_id UUID;
  v_session_status "public"."web_session_status";
  v_device_public_key TEXT;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();

  -- Verify the session exists and is pending
  SELECT "user_id", "status" INTO v_session_user_id, v_session_status
  FROM "public"."web_sessions"
  WHERE "id" = p_session_id;

  IF v_session_user_id IS NULL THEN
    RAISE EXCEPTION 'Web session not found';
  END IF;

  IF v_session_user_id != v_user_id THEN
    RAISE EXCEPTION 'Not authorized to authorize this session';
  END IF;

  IF v_session_status != 'pending' THEN
    RAISE EXCEPTION 'Session is not in pending state';
  END IF;

  -- Verify the device belongs to the user and get its public key
  SELECT "public_key" INTO v_device_public_key
  FROM "public"."devices"
  WHERE "id" = p_device_id
    AND "user_id" = v_user_id
    AND "is_active" = TRUE;

  IF v_device_public_key IS NULL AND NOT EXISTS (
    SELECT 1 FROM "public"."devices"
    WHERE "id" = p_device_id AND "user_id" = v_user_id AND "is_active" = TRUE
  ) THEN
    RAISE EXCEPTION 'Device not found or not active';
  END IF;

  -- Authorize the session
  UPDATE "public"."web_sessions"
  SET
    "status" = 'active',
    "authorizing_device_id" = p_device_id,
    "encrypted_session_key" = p_encrypted_session_key,
    "responder_public_key" = p_responder_public_key,
    "authorizing_device_public_key" = v_device_public_key,
    "permission" = p_permission,
    "session_ttl_seconds" = p_session_ttl_seconds,
    "max_idle_seconds" = p_max_idle_seconds,
    "authorized_at" = NOW(),
    "expires_at" = NOW() + (p_session_ttl_seconds || ' seconds')::INTERVAL,
    "last_activity_at" = NOW()
  WHERE "id" = p_session_id;

  RETURN TRUE;
END;
$$;


ALTER FUNCTION "public"."authorize_web_session_v2"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text", "p_permission" "public"."web_session_permission", "p_session_ttl_seconds" integer, "p_max_idle_seconds" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."authorize_web_session_v2"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text", "p_permission" "public"."web_session_permission", "p_session_ttl_seconds" integer, "p_max_idle_seconds" integer) IS 'Authorizes a pending web session with permission level and TTL controls.';



CREATE OR REPLACE FUNCTION "public"."check_if_authenticated_user_owns_email"("email" character varying) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$ BEGIN -- Check if the email exists in the auth.users table and if the id column matches the (select auth.uid()) function
  IF EXISTS (
    SELECT *
    FROM auth.users
    WHERE (
        auth.users.email = $1
        OR LOWER(auth.users.email) = LOWER($1)
      )
      AND id = (
        SELECT auth.uid()
      )
  ) THEN RETURN TRUE;
ELSE RETURN false;
END IF;
END;
$_$;


ALTER FUNCTION "public"."check_if_authenticated_user_owns_email"("email" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_expired_web_sessions"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  WITH deleted AS (
    DELETE FROM public.web_sessions
    WHERE status = 'pending'
      AND expires_at < NOW()
    RETURNING id
  )
  SELECT COUNT(*) INTO deleted_count FROM deleted;

  -- Also mark expired active sessions
  UPDATE public.web_sessions
  SET status = 'expired'
  WHERE status = 'active'
    AND expires_at < NOW();

  RETURN deleted_count;
END;
$$;


ALTER FUNCTION "public"."cleanup_expired_web_sessions"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cleanup_expired_web_sessions"() IS 'Cleans up expired pending web sessions and marks expired active sessions.';



CREATE OR REPLACE FUNCTION "public"."cleanup_stale_claude_runs"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  ended_count INTEGER;
BEGIN
  WITH ended AS (
    UPDATE "public"."claude_runs"
    SET
      "status" = 'ended'::"public"."coding_session_status",
      "ended_at" = NOW()
    WHERE "status" = 'active'
      AND "last_activity_at" < NOW() - INTERVAL '5 minutes'
    RETURNING "id"
  )
  SELECT COUNT(*) INTO ended_count FROM ended;

  RETURN ended_count;
END;
$$;


ALTER FUNCTION "public"."cleanup_stale_claude_runs"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cleanup_stale_claude_runs"() IS 'Ends Claude runs that have been inactive for more than 5 minutes.';



CREATE OR REPLACE FUNCTION "public"."custom_access_token_hook"("event" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE claims jsonb;
user_role public.app_role;
BEGIN -- Check if the user is marked as admin in the profiles table
SELECT role INTO user_role
FROM public.user_roles
WHERE user_id = (event->>'user_id')::uuid;

    claims := event->'claims';

    IF user_role IS NOT NULL THEN -- Set the claim
claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
ELSE claims := jsonb_set(claims, '{user_role}', 'null');
END IF;

    -- Update the 'claims' object in the original event
event := jsonb_set(event, '{claims}', claims);

    -- Return the modified or original event
RETURN event;
END;
$$;


ALTER FUNCTION "public"."custom_access_token_hook"("event" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_credits"("org_id" "uuid", "amount" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN -- Decrement the credits column by the specified amount
UPDATE organization_credits
SET credits = credits - amount
WHERE organization_id = org_id;
END;
$$;


ALTER FUNCTION "public"."decrement_credits"("org_id" "uuid", "amount" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expire_old_pairing_tokens"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE "public"."pairing_tokens"
  SET
    "status" = 'expired',
    "updated_at" = NOW()
  WHERE
    "status" IN ('pending', 'approved')
    AND "expires_at" < NOW();
END;
$$;


ALTER FUNCTION "public"."expire_old_pairing_tokens"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_user_id"("p_gateway_customer_id" "text") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT user_id FROM public.billing_customers WHERE gateway_customer_id = p_gateway_customer_id;
$$;


ALTER FUNCTION "public"."get_customer_user_id"("p_gateway_customer_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_device_pair_id"("p_device_id_1" "uuid", "p_device_id_2" "uuid") RETURNS TABLE("device_a" "uuid", "device_b" "uuid")
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  -- Return devices in consistent order (smaller UUID first)
  IF p_device_id_1 < p_device_id_2 THEN
    RETURN QUERY SELECT p_device_id_1, p_device_id_2;
  ELSE
    RETURN QUERY SELECT p_device_id_2, p_device_id_1;
  END IF;
END;
$$;


ALTER FUNCTION "public"."get_device_pair_id"("p_device_id_1" "uuid", "p_device_id_2" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_device_pair_id"("p_device_id_1" "uuid", "p_device_id_2" "uuid") IS 'Returns device IDs in consistent order for pairwise secret lookups.';



CREATE OR REPLACE FUNCTION "public"."get_device_trust_chain"("p_device_id" "uuid") RETURNS TABLE("device_id" "uuid", "device_name" "text", "device_role" "public"."device_role", "trust_level" integer, "grantor_device_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE trust_chain AS (
    -- Base case: the device itself
    SELECT
      d."id" AS device_id,
      d."name" AS device_name,
      d."device_role",
      0 AS trust_level,
      NULL::UUID AS grantor_device_id,
      d."user_id"
    FROM "public"."devices" d
    WHERE d."id" = p_device_id

    UNION ALL

    -- Recursive case: find grantor devices
    SELECT
      g."id" AS device_id,
      g."name" AS device_name,
      g."device_role",
      tc.trust_level + 1 AS trust_level,
      dtg."grantor_device_id",
      g."user_id"
    FROM trust_chain tc
    JOIN "public"."device_trust_graph" dtg ON dtg."grantee_device_id" = tc.device_id
    JOIN "public"."devices" g ON g."id" = dtg."grantor_device_id"
    WHERE dtg."status" = 'active'
      AND (dtg."expires_at" IS NULL OR dtg."expires_at" > NOW())
      AND tc.trust_level < 3  -- Max depth
  )
  SELECT
    tc.device_id,
    tc.device_name,
    tc.device_role,
    tc.trust_level,
    tc.grantor_device_id
  FROM trust_chain tc
  ORDER BY tc.trust_level ASC;
END;
$$;


ALTER FUNCTION "public"."get_device_trust_chain"("p_device_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_device_trust_chain"("p_device_id" "uuid") IS 'Returns the trust chain from a device up to the trust root.';



CREATE OR REPLACE FUNCTION "public"."get_run_active_viewers"("p_run_id" "uuid") RETURNS TABLE("viewer_id" "uuid", "viewer_type" "text", "viewer_name" "text", "permission" "public"."web_session_permission", "joined_at" timestamp with time zone, "last_seen_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  -- Verify the user owns this run
  IF NOT EXISTS (
    SELECT 1 FROM "public"."claude_runs"
    WHERE "id" = p_run_id AND "user_id" = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this run';
  END IF;

  RETURN QUERY
  SELECT
    rv."id" AS viewer_id,
    CASE
      WHEN rv."viewer_device_id" IS NOT NULL THEN 'device'
      ELSE 'web_session'
    END AS viewer_type,
    COALESCE(
      d."name",
      'Web Session'
    ) AS viewer_name,
    rv."permission",
    rv."joined_at",
    rv."last_seen_at"
  FROM "public"."run_viewers" rv
  LEFT JOIN "public"."devices" d ON d."id" = rv."viewer_device_id"
  WHERE rv."run_id" = p_run_id
    AND rv."is_active" = TRUE
  ORDER BY rv."joined_at" ASC;
END;
$$;


ALTER FUNCTION "public"."get_run_active_viewers"("p_run_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_run_active_viewers"("p_run_id" "uuid") IS 'Returns all active viewers for a Claude run.';



CREATE OR REPLACE FUNCTION "public"."get_user_devices_with_trust"() RETURNS TABLE("id" "uuid", "name" "text", "device_type" "public"."device_type", "device_role" "public"."device_role", "is_primary_trust_root" boolean, "is_trusted" boolean, "trust_level" integer, "verified_at" timestamp with time zone, "last_seen_at" timestamp with time zone, "is_active" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();

  RETURN QUERY
  SELECT
    d."id",
    d."name",
    d."device_type",
    d."device_role",
    d."is_primary_trust_root",
    COALESCE(
      d."is_primary_trust_root",
      EXISTS (
        SELECT 1 FROM "public"."device_trust_graph" dtg
        WHERE dtg."grantee_device_id" = d."id"
          AND dtg."status" = 'active'
          AND (dtg."expires_at" IS NULL OR dtg."expires_at" > NOW())
      )
    ) AS is_trusted,
    COALESCE(
      (
        SELECT dtg."trust_level"
        FROM "public"."device_trust_graph" dtg
        WHERE dtg."grantee_device_id" = d."id"
          AND dtg."status" = 'active'
        LIMIT 1
      ),
      CASE WHEN d."is_primary_trust_root" THEN 0 ELSE NULL END
    ) AS trust_level,
    d."verified_at",
    d."last_seen_at",
    d."is_active"
  FROM "public"."devices" d
  WHERE d."user_id" = v_user_id
  ORDER BY
    d."is_primary_trust_root" DESC,
    d."device_role",
    d."last_seen_at" DESC NULLS LAST;
END;
$$;


ALTER FUNCTION "public"."get_user_devices_with_trust"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_user_devices_with_trust"() IS 'Returns all devices for the current user with their trust status and level.';



CREATE OR REPLACE FUNCTION "public"."handle_auth_user_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp', 'auth'
    AS $$ BEGIN
INSERT INTO public.user_profiles (id)
VALUES (NEW.id);
INSERT INTO public.user_settings (id)
VALUES (NEW.id);
INSERT INTO public.user_application_settings (id, email_readonly)
VALUES (NEW.id, NEW.email);

RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_auth_user_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_create_welcome_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$ BEGIN
INSERT INTO public.user_notifications (user_id, payload)
VALUES (NEW.id, '{ "type": "welcome" }'::JSONB);
RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_create_welcome_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_application_admin"("user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$ BEGIN RETURN EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_roles.user_id = $1
      AND user_roles.role = 'admin'
  );
END;
$_$;


ALTER FUNCTION "public"."is_application_admin"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_device_trusted"("p_user_id" "uuid", "p_device_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_is_trusted BOOLEAN;
BEGIN
  -- Check if device is the primary trust root
  SELECT EXISTS (
    SELECT 1 FROM "public"."devices"
    WHERE "id" = p_device_id
      AND "user_id" = p_user_id
      AND "is_primary_trust_root" = TRUE
      AND "is_active" = TRUE
  ) INTO v_is_trusted;

  IF v_is_trusted THEN
    RETURN TRUE;
  END IF;

  -- Check if device has active trust relationship
  SELECT EXISTS (
    SELECT 1 FROM "public"."device_trust_graph"
    WHERE "grantee_device_id" = p_device_id
      AND "user_id" = p_user_id
      AND "status" = 'active'
      AND ("expires_at" IS NULL OR "expires_at" > NOW())
  ) INTO v_is_trusted;

  RETURN v_is_trusted;
END;
$$;


ALTER FUNCTION "public"."is_device_trusted"("p_user_id" "uuid", "p_device_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_device_trusted"("p_user_id" "uuid", "p_device_id" "uuid") IS 'Checks if a device is trusted (primary trust root or has active trust relationship).';



CREATE OR REPLACE FUNCTION "public"."is_web_session_valid"("p_session_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_session RECORD;
BEGIN
  SELECT
    "status",
    "expires_at",
    "last_activity_at",
    "max_idle_seconds"
  INTO v_session
  FROM "public"."web_sessions"
  WHERE "id" = p_session_id
    AND "user_id" = auth.uid();

  IF v_session IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Check status
  IF v_session.status != 'active' THEN
    RETURN FALSE;
  END IF;

  -- Check absolute expiry
  IF v_session.expires_at < NOW() THEN
    RETURN FALSE;
  END IF;

  -- Check idle timeout
  IF v_session.last_activity_at + (v_session.max_idle_seconds || ' seconds')::INTERVAL < NOW() THEN
    -- Mark as expired
    UPDATE "public"."web_sessions"
    SET "status" = 'expired'
    WHERE "id" = p_session_id;
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;


ALTER FUNCTION "public"."is_web_session_valid"("p_session_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_web_session_valid"("p_session_id" "uuid") IS 'Checks if a web session is still valid (active, not expired, not idle timeout).';



CREATE OR REPLACE FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only supabase_admin, dashboard_user, postgres can execute this function';
END IF;

INSERT INTO public.user_roles (user_id, role)
VALUES (user_id_arg, 'admin') ON CONFLICT (user_id, role) DO NOTHING;
UPDATE auth.users
SET raw_app_meta_data = jsonb_set(
    COALESCE(raw_app_meta_data, '{}'::jsonb),
    '{user_role}',
    '"admin"'
  )
WHERE id = user_id_arg;

END;
$$;


ALTER FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_web_device_trust"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- If this is a web-browser device and someone tries to set is_trusted = true
  IF NEW."device_type" = 'web-browser' AND NEW."is_trusted" = TRUE THEN
    -- Force it back to false
    NEW."is_trusted" = FALSE;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_web_device_trust"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only  supabase_admin, dashboard_user, postgres can execute this function';
END IF;

DELETE FROM public.user_roles
WHERE user_id = user_id_arg
  AND role = 'admin';

UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data - 'user_role'
WHERE id = user_id_arg
  AND raw_app_meta_data ? 'user_role';
END;
$$;


ALTER FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_device_trust"("p_device_id" "uuid", "p_reason" "text" DEFAULT 'manually_revoked'::"text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id UUID;
  v_revoked_count INTEGER := 0;
BEGIN
  -- Get the user ID and verify ownership
  SELECT "user_id" INTO v_user_id
  FROM "public"."devices"
  WHERE "id" = p_device_id;

  IF v_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to revoke trust for this device';
  END IF;

  -- Revoke all trust relationships where this device is the grantee
  WITH revoked AS (
    UPDATE "public"."device_trust_graph"
    SET
      "status" = 'revoked'::"public"."trust_relationship_status",
      "revoked_at" = NOW(),
      "revoked_reason" = p_reason
    WHERE "grantee_device_id" = p_device_id
      AND "status" = 'active'
    RETURNING "id"
  )
  SELECT COUNT(*) INTO v_revoked_count FROM revoked;

  -- Cascade: revoke trust for devices that this device introduced
  WITH RECURSIVE cascade_revoke AS (
    -- Devices directly introduced by the revoked device
    SELECT "grantee_device_id" AS device_id
    FROM "public"."device_trust_graph"
    WHERE "grantor_device_id" = p_device_id
      AND "status" = 'active'

    UNION ALL

    -- Recursively find devices introduced by those devices
    SELECT dtg."grantee_device_id"
    FROM "public"."device_trust_graph" dtg
    JOIN cascade_revoke cr ON dtg."grantor_device_id" = cr.device_id
    WHERE dtg."status" = 'active'
  ),
  cascade_updated AS (
    UPDATE "public"."device_trust_graph" dtg
    SET
      "status" = 'revoked'::"public"."trust_relationship_status",
      "revoked_at" = NOW(),
      "revoked_reason" = 'cascade_from_' || p_device_id::TEXT
    FROM cascade_revoke cr
    WHERE dtg."grantee_device_id" = cr.device_id
      AND dtg."status" = 'active'
    RETURNING dtg."id"
  )
  SELECT v_revoked_count + COUNT(*) INTO v_revoked_count FROM cascade_updated;

  -- Deactivate the device itself
  UPDATE "public"."devices"
  SET
    "is_active" = FALSE,
    "updated_at" = NOW()
  WHERE "id" = p_device_id;

  RETURN v_revoked_count;
END;
$$;


ALTER FUNCTION "public"."revoke_device_trust"("p_device_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."revoke_device_trust"("p_device_id" "uuid", "p_reason" "text") IS 'Revokes trust for a device and cascades to all devices it introduced.';



CREATE OR REPLACE FUNCTION "public"."revoke_web_session"("p_session_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();

  UPDATE public.web_sessions
  SET
    status = 'revoked',
    revoked_at = NOW(),
    revoked_reason = p_reason
  WHERE id = p_session_id
    AND user_id = v_user_id
    AND status IN ('pending', 'active');

  RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."revoke_web_session"("p_session_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."revoke_web_session"("p_session_id" "uuid", "p_reason" "text") IS 'Revokes an active or pending web session.';



CREATE OR REPLACE FUNCTION "public"."touch_web_session"("p_session_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.web_sessions
  SET last_activity_at = NOW()
  WHERE id = p_session_id
    AND user_id = auth.uid()
    AND status = 'active'
    AND expires_at > NOW();

  RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."touch_web_session"("p_session_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."touch_web_session"("p_session_id" "uuid") IS 'Updates last activity timestamp for a web session.';



CREATE OR REPLACE FUNCTION "public"."update_user_application_settings_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$ BEGIN
UPDATE public.user_application_settings
SET email_readonly = NEW.email
WHERE id = NEW.id;
RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_user_application_settings_email"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."account_delete_tokens" (
    "token" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL
);


ALTER TABLE "public"."account_delete_tokens" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_delete_tokens" IS 'Tokens for account deletion requests.';



CREATE TABLE IF NOT EXISTS "public"."agent_coding_session_messages" (
    "id" bigint NOT NULL,
    "session_id" "uuid" NOT NULL,
    "sequence_number" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "role" "text" DEFAULT 'assistant'::"text" NOT NULL,
    "content_encrypted" "bytea",
    "content_nonce" "bytea"
);


ALTER TABLE "public"."agent_coding_session_messages" OWNER TO "postgres";


COMMENT ON TABLE "public"."agent_coding_session_messages" IS 'Encrypted messages for agent coding sessions. Contains role, encrypted content, and sequence number.';



CREATE TABLE IF NOT EXISTS "public"."agent_coding_session_secrets" (
    "id" bigint NOT NULL,
    "session_id" "uuid" NOT NULL,
    "device_id" "text" NOT NULL,
    "encrypted_secret" "bytea" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."agent_coding_session_secrets" OWNER TO "postgres";


COMMENT ON TABLE "public"."agent_coding_session_secrets" IS 'Encrypted chat secrets for executor to viewer device bootstrap in agent coding sessions.';



CREATE TABLE IF NOT EXISTS "public"."agent_coding_sessions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_id" "uuid" NOT NULL,
    "repository_id" "uuid" NOT NULL,
    "session_pid" integer,
    "session_started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "session_ended_at" timestamp with time zone,
    "status" "public"."coding_session_status" DEFAULT 'active'::"public"."coding_session_status" NOT NULL,
    "current_branch" "text",
    "working_directory" "text",
    "last_heartbeat_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_worktree" boolean DEFAULT false NOT NULL,
    "worktree_path" "text"
);


ALTER TABLE "public"."agent_coding_sessions" OWNER TO "postgres";


COMMENT ON TABLE "public"."agent_coding_sessions" IS 'Active Claude agent coding sessions for two-way mobile communication.';



COMMENT ON COLUMN "public"."agent_coding_sessions"."is_worktree" IS 'Whether this session runs in an isolated git worktree (true) or directly in the main repository directory (false)';



COMMENT ON COLUMN "public"."agent_coding_sessions"."worktree_path" IS 'File path to the worktree directory when is_worktree is true, null otherwise';



CREATE TABLE IF NOT EXISTS "public"."app_settings" (
    "id" boolean DEFAULT true NOT NULL,
    "settings" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "single_row" CHECK ("id")
);


ALTER TABLE "public"."app_settings" OWNER TO "postgres";


COMMENT ON TABLE "public"."app_settings" IS 'Application-wide settings stored in a single row';



CREATE TABLE IF NOT EXISTS "public"."billing_customers" (
    "gateway_customer_id" "text" NOT NULL,
    "gateway_name" "text" NOT NULL,
    "default_currency" "text",
    "billing_email" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "user_id" "uuid"
);


ALTER TABLE "public"."billing_customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_invoices" (
    "gateway_invoice_id" "text" NOT NULL,
    "gateway_customer_id" "text" NOT NULL,
    "gateway_product_id" "text",
    "gateway_price_id" "text",
    "gateway_name" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "currency" "text" NOT NULL,
    "status" "text" NOT NULL,
    "due_date" "date",
    "paid_date" "date",
    "hosted_invoice_url" "text"
);


ALTER TABLE "public"."billing_invoices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_one_time_payments" (
    "gateway_charge_id" "text" NOT NULL,
    "gateway_customer_id" "text" NOT NULL,
    "gateway_name" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "currency" "text" NOT NULL,
    "status" "text" NOT NULL,
    "charge_date" timestamp with time zone NOT NULL,
    "gateway_invoice_id" "text" NOT NULL,
    "gateway_product_id" "text" NOT NULL,
    "gateway_price_id" "text" NOT NULL
);


ALTER TABLE "public"."billing_one_time_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_payment_methods" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gateway_customer_id" "text" NOT NULL,
    "payment_method_id" "text" NOT NULL,
    "payment_method_type" "text" NOT NULL,
    "payment_method_details" "jsonb" NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."billing_payment_methods" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_prices" (
    "gateway_price_id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "gateway_product_id" "text" NOT NULL,
    "currency" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "recurring_interval" "text" NOT NULL,
    "recurring_interval_count" integer DEFAULT 0 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "tier" "text",
    "free_trial_days" integer,
    "gateway_name" "text" NOT NULL
);


ALTER TABLE "public"."billing_prices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_products" (
    "gateway_product_id" "text" NOT NULL,
    "gateway_name" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "features" "jsonb",
    "active" boolean DEFAULT true NOT NULL,
    "is_visible_in_ui" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."billing_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_subscriptions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gateway_customer_id" "text" NOT NULL,
    "gateway_name" "text" NOT NULL,
    "gateway_subscription_id" "text" NOT NULL,
    "gateway_product_id" "text" NOT NULL,
    "gateway_price_id" "text" NOT NULL,
    "status" "public"."subscription_status" NOT NULL,
    "current_period_start" "date" NOT NULL,
    "current_period_end" "date" NOT NULL,
    "currency" "text" NOT NULL,
    "is_trial" boolean NOT NULL,
    "trial_ends_at" "date",
    "cancel_at_period_end" boolean NOT NULL,
    "quantity" integer
);


ALTER TABLE "public"."billing_subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_usage_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gateway_customer_id" "text" NOT NULL,
    "feature" "text" NOT NULL,
    "usage_amount" integer NOT NULL,
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."billing_usage_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_volume_tiers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gateway_price_id" "text" NOT NULL,
    "min_quantity" integer NOT NULL,
    "max_quantity" integer,
    "unit_price" numeric NOT NULL
);


ALTER TABLE "public"."billing_volume_tiers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chats" (
    "id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "project_id" "uuid" NOT NULL
);


ALTER TABLE "public"."chats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."claude_runs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "executor_device_id" "uuid" NOT NULL,
    "coding_session_id" "uuid",
    "run_token_hash" "text" NOT NULL,
    "status" "public"."coding_session_status" DEFAULT 'active'::"public"."coding_session_status" NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "last_activity_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "run_metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."claude_runs" OWNER TO "postgres";


COMMENT ON TABLE "public"."claude_runs" IS 'Active Claude Code runs for multi-viewer streaming. Executor broadcasts to viewers.';



ALTER TABLE "public"."agent_coding_session_secrets" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."coding_session_secrets_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."agent_coding_session_messages" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."conversation_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."device_pairwise_secrets" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_a_id" "uuid" NOT NULL,
    "device_b_id" "uuid" NOT NULL,
    "encrypted_secret_for_a" "text" NOT NULL,
    "encrypted_secret_for_b" "text" NOT NULL,
    "key_algorithm" "text" DEFAULT 'X25519-XChaCha20-Poly1305'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_pairwise_secrets_ordering" CHECK (("device_a_id" < "device_b_id"))
);


ALTER TABLE "public"."device_pairwise_secrets" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_pairwise_secrets" IS 'Encrypted pairwise secrets between device pairs. Each device stores its own encrypted copy.';



CREATE TABLE IF NOT EXISTS "public"."device_trust_graph" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "grantor_device_id" "uuid" NOT NULL,
    "grantee_device_id" "uuid" NOT NULL,
    "status" "public"."trust_relationship_status" DEFAULT 'pending'::"public"."trust_relationship_status" NOT NULL,
    "trust_level" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "approved_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "revoked_reason" "text",
    CONSTRAINT "device_trust_graph_different_devices" CHECK (("grantor_device_id" <> "grantee_device_id")),
    CONSTRAINT "device_trust_graph_trust_level_check" CHECK ((("trust_level" >= 1) AND ("trust_level" <= 3)))
);


ALTER TABLE "public"."device_trust_graph" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_trust_graph" IS 'Trust relationships between devices. Trust flows from trust_root (phone) to executors and viewers.';



CREATE TABLE IF NOT EXISTS "public"."devices" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "device_type" "public"."device_type" NOT NULL,
    "hostname" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "device_role" "public"."device_role" DEFAULT 'trusted_executor'::"public"."device_role" NOT NULL,
    "public_key" "text",
    "is_primary_trust_root" boolean DEFAULT false NOT NULL,
    "verified_at" timestamp with time zone,
    "apns_token" "text",
    "apns_environment" "text" DEFAULT 'sandbox'::"text",
    "push_enabled" boolean DEFAULT false NOT NULL,
    "apns_token_updated_at" timestamp with time zone,
    "is_trusted" boolean DEFAULT false NOT NULL,
    "has_seen_trust_prompt" boolean DEFAULT false NOT NULL,
    CONSTRAINT "check_web_devices_not_trusted" CHECK ((("device_type" <> 'web-browser'::"public"."device_type") OR ("is_trusted" = false))),
    CONSTRAINT "devices_apns_environment_check" CHECK (("apns_environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"])))
);


ALTER TABLE "public"."devices" OWNER TO "postgres";


COMMENT ON TABLE "public"."devices" IS 'Registered devices (Mac, Linux, Windows) for remote CLI access.';



COMMENT ON COLUMN "public"."devices"."device_role" IS 'Role in trust hierarchy: trust_root (phone), trusted_executor (mac), temporary_viewer (web)';



COMMENT ON COLUMN "public"."devices"."public_key" IS 'X25519 long-term public key for device (base64 encoded)';



COMMENT ON COLUMN "public"."devices"."is_primary_trust_root" IS 'Whether this is the primary trust root device for the user (only one allowed)';



COMMENT ON COLUMN "public"."devices"."verified_at" IS 'When this device was verified/approved by the trust root';



COMMENT ON COLUMN "public"."devices"."apns_token" IS 'APNs device token for push notifications (hex-encoded)';



COMMENT ON COLUMN "public"."devices"."apns_environment" IS 'APNs environment: sandbox for development, production for App Store builds';



COMMENT ON COLUMN "public"."devices"."push_enabled" IS 'Whether push notifications are enabled for this device';



COMMENT ON COLUMN "public"."devices"."apns_token_updated_at" IS 'When the APNs token was last updated';



COMMENT ON COLUMN "public"."devices"."is_trusted" IS 'Whether this device is marked as trusted by the user. Defaults to false. Web-browser devices can NEVER be trusted.';



COMMENT ON COLUMN "public"."devices"."has_seen_trust_prompt" IS 'Whether the user has been shown the trust onboarding prompt for this device.';



COMMENT ON CONSTRAINT "check_web_devices_not_trusted" ON "public"."devices" IS 'Ensures web-browser devices cannot be marked as trusted.';



CREATE TABLE IF NOT EXISTS "public"."live_activity_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_id" "uuid" NOT NULL,
    "activity_id" "text" NOT NULL,
    "push_token" "text" NOT NULL,
    "apns_environment" "text" DEFAULT 'sandbox'::"text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "live_activity_tokens_apns_environment_check" CHECK (("apns_environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"])))
);


ALTER TABLE "public"."live_activity_tokens" OWNER TO "postgres";


COMMENT ON TABLE "public"."live_activity_tokens" IS 'Stores push tokens for iOS Live Activity instances for APNs updates';



COMMENT ON COLUMN "public"."live_activity_tokens"."activity_id" IS 'The Activity ID from ActivityKit (unique per activity instance)';



COMMENT ON COLUMN "public"."live_activity_tokens"."push_token" IS 'APNs push token for this specific Live Activity (hex-encoded)';



COMMENT ON COLUMN "public"."live_activity_tokens"."apns_environment" IS 'APNs environment: sandbox for development, production for App Store';



COMMENT ON COLUMN "public"."live_activity_tokens"."is_active" IS 'Whether this activity is still active (false when ended)';



CREATE TABLE IF NOT EXISTS "public"."marketing_author_profiles" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "slug" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "bio" "text" NOT NULL,
    "avatar_url" "text" NOT NULL,
    "website_url" "text",
    "twitter_handle" "text",
    "facebook_handle" "text",
    "linkedin_handle" "text",
    "instagram_handle" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."marketing_author_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_blog_author_posts" (
    "author_id" "uuid" NOT NULL,
    "post_id" "uuid" NOT NULL
);


ALTER TABLE "public"."marketing_blog_author_posts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_blog_post_tags_relationship" (
    "blog_post_id" "uuid" NOT NULL,
    "tag_id" "uuid" NOT NULL
);


ALTER TABLE "public"."marketing_blog_post_tags_relationship" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_blog_posts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "slug" "text" NOT NULL,
    "title" "text" NOT NULL,
    "summary" "text" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "is_featured" boolean DEFAULT false NOT NULL,
    "status" "public"."marketing_blog_post_status" DEFAULT 'draft'::"public"."marketing_blog_post_status" NOT NULL,
    "cover_image" "text",
    "seo_data" "jsonb",
    "json_content" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "media_type" character varying,
    "media_poster" "text",
    CONSTRAINT "marketing_blog_posts_media_type_check" CHECK ((("media_type" IS NULL) OR (("media_type")::"text" = ANY ((ARRAY['image'::character varying, 'video'::character varying, 'gif'::character varying])::"text"[]))))
);


ALTER TABLE "public"."marketing_blog_posts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."marketing_blog_posts"."media_type" IS 'Type of cover media: image, video, or gif';



COMMENT ON COLUMN "public"."marketing_blog_posts"."media_poster" IS 'Poster/thumbnail image URL for videos';



CREATE TABLE IF NOT EXISTS "public"."marketing_changelog" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "title" character varying(255) NOT NULL,
    "json_content" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "cover_image" "text",
    "status" "public"."marketing_changelog_status" DEFAULT 'draft'::"public"."marketing_changelog_status" NOT NULL,
    "version" character varying(20),
    "tags" "text"[] DEFAULT '{}'::"text"[],
    "media_type" character varying(20),
    "media_url" "text",
    "media_alt" "text",
    "technical_details" "text",
    "media_poster" "text",
    CONSTRAINT "marketing_changelog_media_type_check" CHECK ((("media_type" IS NULL) OR (("media_type")::"text" = ANY ((ARRAY['image'::character varying, 'video'::character varying, 'gif'::character varying])::"text"[]))))
);


ALTER TABLE "public"."marketing_changelog" OWNER TO "postgres";


COMMENT ON COLUMN "public"."marketing_changelog"."media_poster" IS 'Poster/thumbnail image URL for videos';



CREATE TABLE IF NOT EXISTS "public"."marketing_changelog_author_relationship" (
    "author_id" "uuid" NOT NULL,
    "changelog_id" "uuid" NOT NULL
);


ALTER TABLE "public"."marketing_changelog_author_relationship" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_board_subscriptions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "board_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."marketing_feedback_board_subscriptions" OWNER TO "postgres";


COMMENT ON TABLE "public"."marketing_feedback_board_subscriptions" IS 'Tracks user subscriptions to feedback boards';



CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_boards" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "slug" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "created_by" "uuid" NOT NULL,
    "settings" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "color" "text"
);


ALTER TABLE "public"."marketing_feedback_boards" OWNER TO "postgres";


COMMENT ON TABLE "public"."marketing_feedback_boards" IS 'Feedback boards that organize and group different feedback threads';



COMMENT ON COLUMN "public"."marketing_feedback_boards"."color" IS 'Optional color identifier for the board';



CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_comment_reactions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "comment_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "reaction_type" "public"."marketing_feedback_reaction_type" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."marketing_feedback_comment_reactions" OWNER TO "postgres";


COMMENT ON TABLE "public"."marketing_feedback_comment_reactions" IS 'Tracks user reactions to feedback comments';



CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_comments" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "moderator_hold_category" "public"."marketing_feedback_moderator_hold_category"
);


ALTER TABLE "public"."marketing_feedback_comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_thread_reactions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "reaction_type" "public"."marketing_feedback_reaction_type" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."marketing_feedback_thread_reactions" OWNER TO "postgres";


COMMENT ON TABLE "public"."marketing_feedback_thread_reactions" IS 'Tracks user reactions to feedback threads';



CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_thread_subscriptions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."marketing_feedback_thread_subscriptions" OWNER TO "postgres";


COMMENT ON TABLE "public"."marketing_feedback_thread_subscriptions" IS 'Tracks user subscriptions to feedback threads';



CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_threads" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "title" character varying(255) NOT NULL,
    "content" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "priority" "public"."marketing_feedback_thread_priority" DEFAULT 'low'::"public"."marketing_feedback_thread_priority" NOT NULL,
    "type" "public"."marketing_feedback_thread_type" DEFAULT 'general'::"public"."marketing_feedback_thread_type" NOT NULL,
    "status" "public"."marketing_feedback_thread_status" DEFAULT 'open'::"public"."marketing_feedback_thread_status" NOT NULL,
    "added_to_roadmap" boolean DEFAULT false NOT NULL,
    "open_for_public_discussion" boolean DEFAULT false NOT NULL,
    "is_publicly_visible" boolean DEFAULT false NOT NULL,
    "moderator_hold_category" "public"."marketing_feedback_moderator_hold_category",
    "board_id" "uuid"
);


ALTER TABLE "public"."marketing_feedback_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."marketing_tags" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."marketing_tags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pairing_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "requesting_device_id" "uuid" NOT NULL,
    "requesting_device_name" "text" NOT NULL,
    "requesting_device_type" "public"."device_type" NOT NULL,
    "token" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "status" "public"."pairing_token_status" DEFAULT 'pending'::"public"."pairing_token_status" NOT NULL,
    "approving_device_id" "uuid",
    "relay_session_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    CONSTRAINT "completed_has_approver" CHECK (((("status" = 'completed'::"public"."pairing_token_status") AND ("approving_device_id" IS NOT NULL)) OR ("status" <> 'completed'::"public"."pairing_token_status"))),
    CONSTRAINT "completed_has_timestamp" CHECK (((("status" = 'completed'::"public"."pairing_token_status") AND ("completed_at" IS NOT NULL)) OR (("status" <> 'completed'::"public"."pairing_token_status") AND ("completed_at" IS NULL)))),
    CONSTRAINT "valid_expiry" CHECK (("expires_at" > "created_at"))
);


ALTER TABLE "public"."pairing_tokens" OWNER TO "postgres";


COMMENT ON TABLE "public"."pairing_tokens" IS 'Time-limited tokens for QR-based device pairing between iOS and macOS apps';



COMMENT ON COLUMN "public"."pairing_tokens"."token" IS 'Short alphanumeric token (8 chars) displayed in QR code';



COMMENT ON COLUMN "public"."pairing_tokens"."relay_session_id" IS 'UUID for coordinating WebSocket connection on relay server';



CREATE TABLE IF NOT EXISTS "public"."repositories" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "local_path" "text" NOT NULL,
    "remote_url" "text",
    "default_branch" "text",
    "parent_repository_id" "uuid",
    "is_worktree" boolean DEFAULT false NOT NULL,
    "worktree_branch" "text",
    "status" "public"."repository_status" DEFAULT 'active'::"public"."repository_status" NOT NULL,
    "last_synced_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."repositories" OWNER TO "postgres";


COMMENT ON TABLE "public"."repositories" IS 'Git repositories registered for remote access. Supports worktree consolidation.';



CREATE TABLE IF NOT EXISTS "public"."run_viewers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "run_id" "uuid" NOT NULL,
    "viewer_device_id" "uuid",
    "viewer_web_session_id" "uuid",
    "permission" "public"."web_session_permission" DEFAULT 'view_only'::"public"."web_session_permission" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "left_at" timestamp with time zone,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "viewer_session_public_key" "text",
    CONSTRAINT "run_viewers_exactly_one_viewer" CHECK ((((("viewer_device_id" IS NOT NULL))::integer + (("viewer_web_session_id" IS NOT NULL))::integer) = 1))
);


ALTER TABLE "public"."run_viewers" OWNER TO "postgres";


COMMENT ON TABLE "public"."run_viewers" IS 'Viewers connected to Claude runs. Supports both device and web session viewers.';



CREATE TABLE IF NOT EXISTS "public"."user_api_keys" (
    "key_id" "text" NOT NULL,
    "masked_key" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "expires_at" timestamp with time zone,
    "is_revoked" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."user_api_keys" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_api_keys" IS 'API keys for each user.';



CREATE TABLE IF NOT EXISTS "public"."user_application_settings" (
    "id" "uuid" NOT NULL,
    "email_readonly" character varying NOT NULL
);


ALTER TABLE "public"."user_application_settings" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_application_settings" IS 'These settings are updated by the application. Do not use this table to update the user email.';



CREATE TABLE IF NOT EXISTS "public"."user_notifications" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "is_read" boolean DEFAULT false NOT NULL,
    "is_seen" boolean DEFAULT false NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."user_notifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_notifications" IS 'User notifications including the payload, read status, and creation timestamp.';



CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "full_name" character varying,
    "avatar_url" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_profiles" IS 'Stores public user profile information including full name, avatar URL, and creation timestamp.';



CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."app_role" NOT NULL
);


ALTER TABLE "public"."user_roles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_roles" IS 'Application roles for each user.';



CREATE TABLE IF NOT EXISTS "public"."user_settings" (
    "id" "uuid" NOT NULL
);


ALTER TABLE "public"."user_settings" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_settings" IS 'Stores user settings including the default organization.';



CREATE TABLE IF NOT EXISTS "public"."web_sessions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "authorizing_device_id" "uuid",
    "session_token_hash" "text" NOT NULL,
    "web_public_key" "text" NOT NULL,
    "encrypted_session_key" "text",
    "responder_public_key" "text",
    "user_agent" "text",
    "ip_address" "inet",
    "browser_fingerprint" "text",
    "status" "public"."web_session_status" DEFAULT 'pending'::"public"."web_session_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "authorized_at" timestamp with time zone,
    "expires_at" timestamp with time zone NOT NULL,
    "last_activity_at" timestamp with time zone DEFAULT "now"(),
    "revoked_at" timestamp with time zone,
    "revoked_reason" "text",
    "permission" "public"."web_session_permission" DEFAULT 'view_only'::"public"."web_session_permission" NOT NULL,
    "max_idle_seconds" integer DEFAULT 1800 NOT NULL,
    "session_ttl_seconds" integer DEFAULT 86400 NOT NULL,
    "authorizing_device_public_key" "text"
);


ALTER TABLE "public"."web_sessions" OWNER TO "postgres";


COMMENT ON TABLE "public"."web_sessions" IS 'Browser-based sessions with QR-based device authorization for secure web access.';



COMMENT ON COLUMN "public"."web_sessions"."permission" IS 'Permission level: view_only, interact, or full_control';



COMMENT ON COLUMN "public"."web_sessions"."max_idle_seconds" IS 'Max idle time in seconds before session expires (default 30 min)';



COMMENT ON COLUMN "public"."web_sessions"."session_ttl_seconds" IS 'Total session lifetime in seconds (default 24 hours)';



COMMENT ON COLUMN "public"."web_sessions"."authorizing_device_public_key" IS 'Long-term public key of authorizing device for trust verification';



ALTER TABLE ONLY "public"."account_delete_tokens"
    ADD CONSTRAINT "account_delete_tokens_pkey" PRIMARY KEY ("token");



ALTER TABLE ONLY "public"."app_settings"
    ADD CONSTRAINT "app_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_customers"
    ADD CONSTRAINT "billing_customers_gateway_name_gateway_customer_id_key" UNIQUE ("gateway_name", "gateway_customer_id");



ALTER TABLE ONLY "public"."billing_customers"
    ADD CONSTRAINT "billing_customers_pkey" PRIMARY KEY ("gateway_customer_id");



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_gateway_name_gateway_invoice_id_key" UNIQUE ("gateway_name", "gateway_invoice_id");



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_pkey" PRIMARY KEY ("gateway_invoice_id");



ALTER TABLE ONLY "public"."billing_one_time_payments"
    ADD CONSTRAINT "billing_one_time_payments_pkey" PRIMARY KEY ("gateway_charge_id");



ALTER TABLE ONLY "public"."billing_payment_methods"
    ADD CONSTRAINT "billing_payment_methods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_prices"
    ADD CONSTRAINT "billing_prices_gateway_name_gateway_price_id_key" UNIQUE ("gateway_name", "gateway_price_id");



ALTER TABLE ONLY "public"."billing_prices"
    ADD CONSTRAINT "billing_prices_pkey" PRIMARY KEY ("gateway_price_id");



ALTER TABLE ONLY "public"."billing_products"
    ADD CONSTRAINT "billing_products_gateway_name_gateway_product_id_key" UNIQUE ("gateway_name", "gateway_product_id");



ALTER TABLE ONLY "public"."billing_products"
    ADD CONSTRAINT "billing_products_pkey" PRIMARY KEY ("gateway_product_id");



ALTER TABLE ONLY "public"."billing_subscriptions"
    ADD CONSTRAINT "billing_subscriptions_gateway_name_gateway_subscription_id_key" UNIQUE ("gateway_name", "gateway_subscription_id");



ALTER TABLE ONLY "public"."billing_subscriptions"
    ADD CONSTRAINT "billing_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_usage_logs"
    ADD CONSTRAINT "billing_usage_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_volume_tiers"
    ADD CONSTRAINT "billing_volume_tiers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."claude_runs"
    ADD CONSTRAINT "claude_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_coding_session_secrets"
    ADD CONSTRAINT "coding_session_secrets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_coding_sessions"
    ADD CONSTRAINT "coding_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_coding_session_messages"
    ADD CONSTRAINT "conversation_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_pairwise_secrets"
    ADD CONSTRAINT "device_pairwise_secrets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_pairwise_secrets"
    ADD CONSTRAINT "device_pairwise_secrets_unique_pair" UNIQUE ("device_a_id", "device_b_id");



ALTER TABLE ONLY "public"."device_trust_graph"
    ADD CONSTRAINT "device_trust_graph_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_trust_graph"
    ADD CONSTRAINT "device_trust_graph_unique_relationship" UNIQUE ("grantor_device_id", "grantee_device_id");



ALTER TABLE ONLY "public"."devices"
    ADD CONSTRAINT "devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."live_activity_tokens"
    ADD CONSTRAINT "live_activity_tokens_device_id_activity_id_key" UNIQUE ("device_id", "activity_id");



ALTER TABLE ONLY "public"."live_activity_tokens"
    ADD CONSTRAINT "live_activity_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_author_profiles"
    ADD CONSTRAINT "marketing_author_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_author_profiles"
    ADD CONSTRAINT "marketing_author_profiles_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."marketing_blog_posts"
    ADD CONSTRAINT "marketing_blog_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_blog_posts"
    ADD CONSTRAINT "marketing_blog_posts_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."marketing_changelog"
    ADD CONSTRAINT "marketing_changelog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_feedback_board_subscriptions"
    ADD CONSTRAINT "marketing_feedback_board_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_feedback_boards"
    ADD CONSTRAINT "marketing_feedback_boards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_feedback_boards"
    ADD CONSTRAINT "marketing_feedback_boards_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."marketing_feedback_comment_reactions"
    ADD CONSTRAINT "marketing_feedback_comment_reactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_feedback_comments"
    ADD CONSTRAINT "marketing_feedback_comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_feedback_thread_reactions"
    ADD CONSTRAINT "marketing_feedback_thread_reactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_feedback_thread_subscriptions"
    ADD CONSTRAINT "marketing_feedback_thread_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_feedback_threads"
    ADD CONSTRAINT "marketing_feedback_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_tags"
    ADD CONSTRAINT "marketing_tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."marketing_tags"
    ADD CONSTRAINT "marketing_tags_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."pairing_tokens"
    ADD CONSTRAINT "pairing_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pairing_tokens"
    ADD CONSTRAINT "pairing_tokens_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."repositories"
    ADD CONSTRAINT "repositories_device_id_local_path_key" UNIQUE ("device_id", "local_path");



ALTER TABLE ONLY "public"."repositories"
    ADD CONSTRAINT "repositories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."run_viewers"
    ADD CONSTRAINT "run_viewers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_api_keys"
    ADD CONSTRAINT "user_api_keys_pkey" PRIMARY KEY ("key_id");



ALTER TABLE ONLY "public"."user_application_settings"
    ADD CONSTRAINT "user_application_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_role_key" UNIQUE ("user_id", "role");



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."web_sessions"
    ADD CONSTRAINT "web_sessions_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_account_delete_tokens_user_id" ON "public"."account_delete_tokens" USING "btree" ("user_id");



CREATE INDEX "idx_agent_coding_session_messages_session_id" ON "public"."agent_coding_session_messages" USING "btree" ("session_id");



CREATE UNIQUE INDEX "idx_agent_coding_session_messages_session_sequence" ON "public"."agent_coding_session_messages" USING "btree" ("session_id", "sequence_number");



CREATE UNIQUE INDEX "idx_agent_coding_session_secrets_session_device" ON "public"."agent_coding_session_secrets" USING "btree" ("session_id", "device_id");



CREATE INDEX "idx_agent_coding_session_secrets_session_id" ON "public"."agent_coding_session_secrets" USING "btree" ("session_id");



CREATE INDEX "idx_agent_coding_sessions_device_id" ON "public"."agent_coding_sessions" USING "btree" ("device_id");



CREATE INDEX "idx_agent_coding_sessions_device_status" ON "public"."agent_coding_sessions" USING "btree" ("device_id", "status");



CREATE INDEX "idx_agent_coding_sessions_is_worktree" ON "public"."agent_coding_sessions" USING "btree" ("is_worktree");



CREATE INDEX "idx_agent_coding_sessions_last_heartbeat" ON "public"."agent_coding_sessions" USING "btree" ("last_heartbeat_at");



CREATE INDEX "idx_agent_coding_sessions_repo_worktree" ON "public"."agent_coding_sessions" USING "btree" ("repository_id", "is_worktree");



CREATE INDEX "idx_agent_coding_sessions_repository_id" ON "public"."agent_coding_sessions" USING "btree" ("repository_id");



CREATE INDEX "idx_agent_coding_sessions_status" ON "public"."agent_coding_sessions" USING "btree" ("status");



CREATE INDEX "idx_agent_coding_sessions_user_id" ON "public"."agent_coding_sessions" USING "btree" ("user_id");



CREATE INDEX "idx_agent_coding_sessions_user_status" ON "public"."agent_coding_sessions" USING "btree" ("user_id", "status");



CREATE INDEX "idx_billing_invoices_gateway_customer_id" ON "public"."billing_invoices" USING "btree" ("gateway_customer_id");



CREATE INDEX "idx_billing_invoices_gateway_name" ON "public"."billing_invoices" USING "btree" ("gateway_name");



CREATE INDEX "idx_billing_invoices_price_id" ON "public"."billing_invoices" USING "btree" ("gateway_price_id");



CREATE INDEX "idx_billing_invoices_product_id" ON "public"."billing_invoices" USING "btree" ("gateway_product_id");



CREATE INDEX "idx_billing_one_time_payments_customer_id" ON "public"."billing_one_time_payments" USING "btree" ("gateway_customer_id");



CREATE INDEX "idx_billing_one_time_payments_invoice_id" ON "public"."billing_one_time_payments" USING "btree" ("gateway_invoice_id");



CREATE INDEX "idx_billing_one_time_payments_price_id" ON "public"."billing_one_time_payments" USING "btree" ("gateway_price_id");



CREATE INDEX "idx_billing_one_time_payments_product_id" ON "public"."billing_one_time_payments" USING "btree" ("gateway_product_id");



CREATE INDEX "idx_billing_payment_methods_customer_id" ON "public"."billing_payment_methods" USING "btree" ("gateway_customer_id");



CREATE INDEX "idx_billing_payment_methods_payment_method_id" ON "public"."billing_payment_methods" USING "btree" ("payment_method_id");



CREATE INDEX "idx_billing_payment_methods_payment_method_type" ON "public"."billing_payment_methods" USING "btree" ("payment_method_type");



CREATE INDEX "idx_billing_products_gateway_name" ON "public"."billing_products" USING "btree" ("gateway_name");



CREATE INDEX "idx_billing_products_gateway_product_id" ON "public"."billing_products" USING "btree" ("gateway_product_id");



CREATE INDEX "idx_billing_subscriptions_customer_id" ON "public"."billing_subscriptions" USING "btree" ("gateway_customer_id");



CREATE INDEX "idx_billing_subscriptions_plan_id" ON "public"."billing_subscriptions" USING "btree" ("gateway_product_id");



CREATE INDEX "idx_billing_usage_logs_gateway_customer_id" ON "public"."billing_usage_logs" USING "btree" ("gateway_customer_id");



CREATE INDEX "idx_chats_project_id" ON "public"."chats" USING "btree" ("project_id");



CREATE INDEX "idx_chats_user_id" ON "public"."chats" USING "btree" ("user_id");



CREATE INDEX "idx_claude_runs_active" ON "public"."claude_runs" USING "btree" ("user_id", "status") WHERE ("status" = 'active'::"public"."coding_session_status");



CREATE INDEX "idx_claude_runs_coding_session" ON "public"."claude_runs" USING "btree" ("coding_session_id");



CREATE INDEX "idx_claude_runs_executor_device" ON "public"."claude_runs" USING "btree" ("executor_device_id");



CREATE INDEX "idx_claude_runs_last_activity" ON "public"."claude_runs" USING "btree" ("last_activity_at");



CREATE INDEX "idx_claude_runs_status" ON "public"."claude_runs" USING "btree" ("status");



CREATE INDEX "idx_claude_runs_token_hash" ON "public"."claude_runs" USING "btree" ("run_token_hash");



CREATE INDEX "idx_claude_runs_user_id" ON "public"."claude_runs" USING "btree" ("user_id");



CREATE INDEX "idx_device_pairwise_secrets_device_a" ON "public"."device_pairwise_secrets" USING "btree" ("device_a_id");



CREATE INDEX "idx_device_pairwise_secrets_device_b" ON "public"."device_pairwise_secrets" USING "btree" ("device_b_id");



CREATE INDEX "idx_device_pairwise_secrets_user_id" ON "public"."device_pairwise_secrets" USING "btree" ("user_id");



CREATE INDEX "idx_device_trust_graph_active" ON "public"."device_trust_graph" USING "btree" ("grantee_device_id", "status") WHERE ("status" = 'active'::"public"."trust_relationship_status");



CREATE INDEX "idx_device_trust_graph_grantee" ON "public"."device_trust_graph" USING "btree" ("grantee_device_id");



CREATE INDEX "idx_device_trust_graph_grantor" ON "public"."device_trust_graph" USING "btree" ("grantor_device_id");



CREATE INDEX "idx_device_trust_graph_status" ON "public"."device_trust_graph" USING "btree" ("status");



CREATE INDEX "idx_device_trust_graph_user_id" ON "public"."device_trust_graph" USING "btree" ("user_id");



CREATE INDEX "idx_devices_apns_token" ON "public"."devices" USING "btree" ("apns_token") WHERE ("apns_token" IS NOT NULL);



CREATE INDEX "idx_devices_device_role" ON "public"."devices" USING "btree" ("device_role");



CREATE INDEX "idx_devices_is_active" ON "public"."devices" USING "btree" ("is_active");



CREATE INDEX "idx_devices_is_trusted" ON "public"."devices" USING "btree" ("user_id", "is_trusted") WHERE (("is_trusted" = true) AND ("device_type" <> 'web-browser'::"public"."device_type"));



CREATE INDEX "idx_devices_last_seen" ON "public"."devices" USING "btree" ("last_seen_at");



CREATE UNIQUE INDEX "idx_devices_primary_trust_root_unique" ON "public"."devices" USING "btree" ("user_id") WHERE ("is_primary_trust_root" = true);



CREATE INDEX "idx_devices_push_enabled" ON "public"."devices" USING "btree" ("user_id", "push_enabled") WHERE ("push_enabled" = true);



CREATE INDEX "idx_devices_user_id" ON "public"."devices" USING "btree" ("user_id");



CREATE INDEX "idx_devices_verified" ON "public"."devices" USING "btree" ("user_id", "verified_at") WHERE ("verified_at" IS NOT NULL);



CREATE INDEX "idx_live_activity_tokens_active" ON "public"."live_activity_tokens" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_live_activity_tokens_device_id" ON "public"."live_activity_tokens" USING "btree" ("device_id");



CREATE INDEX "idx_marketing_blog_author_posts_author_id" ON "public"."marketing_blog_author_posts" USING "btree" ("author_id");



CREATE INDEX "idx_marketing_blog_author_posts_post_id" ON "public"."marketing_blog_author_posts" USING "btree" ("post_id");



CREATE INDEX "idx_marketing_blog_post_tags_relationship_blog_post_id" ON "public"."marketing_blog_post_tags_relationship" USING "btree" ("blog_post_id");



CREATE INDEX "idx_marketing_blog_post_tags_relationship_tag_id" ON "public"."marketing_blog_post_tags_relationship" USING "btree" ("tag_id");



CREATE INDEX "idx_marketing_changelog_author_relationship_author_id" ON "public"."marketing_changelog_author_relationship" USING "btree" ("author_id");



CREATE INDEX "idx_marketing_changelog_author_relationship_changelog_id" ON "public"."marketing_changelog_author_relationship" USING "btree" ("changelog_id");



CREATE INDEX "idx_marketing_changelog_tags" ON "public"."marketing_changelog" USING "gin" ("tags");



CREATE INDEX "idx_marketing_changelog_version" ON "public"."marketing_changelog" USING "btree" ("version");



CREATE INDEX "idx_marketing_feedback_board_subscriptions_board_id" ON "public"."marketing_feedback_board_subscriptions" USING "btree" ("board_id");



CREATE INDEX "idx_marketing_feedback_board_subscriptions_user_id" ON "public"."marketing_feedback_board_subscriptions" USING "btree" ("user_id");



CREATE INDEX "idx_marketing_feedback_boards_created_by" ON "public"."marketing_feedback_boards" USING "btree" ("created_by");



CREATE INDEX "idx_marketing_feedback_comment_reactions_comment_id" ON "public"."marketing_feedback_comment_reactions" USING "btree" ("comment_id");



CREATE INDEX "idx_marketing_feedback_comment_reactions_user_id" ON "public"."marketing_feedback_comment_reactions" USING "btree" ("user_id");



CREATE INDEX "idx_marketing_feedback_comments_thread_id" ON "public"."marketing_feedback_comments" USING "btree" ("thread_id");



CREATE INDEX "idx_marketing_feedback_comments_user_id" ON "public"."marketing_feedback_comments" USING "btree" ("user_id");



CREATE INDEX "idx_marketing_feedback_thread_reactions_thread_id" ON "public"."marketing_feedback_thread_reactions" USING "btree" ("thread_id");



CREATE INDEX "idx_marketing_feedback_thread_reactions_user_id" ON "public"."marketing_feedback_thread_reactions" USING "btree" ("user_id");



CREATE INDEX "idx_marketing_feedback_thread_subscriptions_thread_id" ON "public"."marketing_feedback_thread_subscriptions" USING "btree" ("thread_id");



CREATE INDEX "idx_marketing_feedback_thread_subscriptions_user_id" ON "public"."marketing_feedback_thread_subscriptions" USING "btree" ("user_id");



CREATE INDEX "idx_marketing_feedback_threads_board_id" ON "public"."marketing_feedback_threads" USING "btree" ("board_id");



CREATE INDEX "idx_marketing_feedback_threads_user_id" ON "public"."marketing_feedback_threads" USING "btree" ("user_id");



CREATE INDEX "idx_pairing_tokens_expires_at" ON "public"."pairing_tokens" USING "btree" ("expires_at");



CREATE INDEX "idx_pairing_tokens_relay_session_id" ON "public"."pairing_tokens" USING "btree" ("relay_session_id");



CREATE INDEX "idx_pairing_tokens_status" ON "public"."pairing_tokens" USING "btree" ("status");



CREATE INDEX "idx_pairing_tokens_token" ON "public"."pairing_tokens" USING "btree" ("token");



CREATE INDEX "idx_pairing_tokens_user_id" ON "public"."pairing_tokens" USING "btree" ("user_id");



CREATE INDEX "idx_repositories_device_id" ON "public"."repositories" USING "btree" ("device_id");



CREATE INDEX "idx_repositories_is_worktree" ON "public"."repositories" USING "btree" ("is_worktree");



CREATE INDEX "idx_repositories_parent_repository_id" ON "public"."repositories" USING "btree" ("parent_repository_id");



CREATE INDEX "idx_repositories_remote_url" ON "public"."repositories" USING "btree" ("remote_url");



CREATE INDEX "idx_repositories_status" ON "public"."repositories" USING "btree" ("status");



CREATE INDEX "idx_repositories_user_id" ON "public"."repositories" USING "btree" ("user_id");



CREATE INDEX "idx_run_viewers_active" ON "public"."run_viewers" USING "btree" ("run_id", "is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_run_viewers_device" ON "public"."run_viewers" USING "btree" ("viewer_device_id");



CREATE INDEX "idx_run_viewers_run_id" ON "public"."run_viewers" USING "btree" ("run_id");



CREATE UNIQUE INDEX "idx_run_viewers_unique_device" ON "public"."run_viewers" USING "btree" ("run_id", "viewer_device_id") WHERE (("viewer_device_id" IS NOT NULL) AND ("is_active" = true));



CREATE UNIQUE INDEX "idx_run_viewers_unique_web_session" ON "public"."run_viewers" USING "btree" ("run_id", "viewer_web_session_id") WHERE (("viewer_web_session_id" IS NOT NULL) AND ("is_active" = true));



CREATE INDEX "idx_run_viewers_web_session" ON "public"."run_viewers" USING "btree" ("viewer_web_session_id");



CREATE UNIQUE INDEX "idx_unique_board_subscription" ON "public"."marketing_feedback_board_subscriptions" USING "btree" ("user_id", "board_id");



CREATE UNIQUE INDEX "idx_unique_comment_user_reaction" ON "public"."marketing_feedback_comment_reactions" USING "btree" ("comment_id", "user_id", "reaction_type");



CREATE UNIQUE INDEX "idx_unique_thread_subscription" ON "public"."marketing_feedback_thread_subscriptions" USING "btree" ("user_id", "thread_id");



CREATE UNIQUE INDEX "idx_unique_thread_user_reaction" ON "public"."marketing_feedback_thread_reactions" USING "btree" ("thread_id", "user_id", "reaction_type");



CREATE INDEX "idx_user_api_keys_user_id" ON "public"."user_api_keys" USING "btree" ("user_id");



CREATE INDEX "idx_user_application_settings_email_readonly" ON "public"."user_application_settings" USING "btree" ("email_readonly");



CREATE INDEX "idx_user_notifications_user_created" ON "public"."user_notifications" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_user_notifications_user_id" ON "public"."user_notifications" USING "btree" ("user_id");



CREATE INDEX "idx_user_roles_user_id" ON "public"."user_roles" USING "btree" ("user_id");



CREATE INDEX "idx_web_sessions_authorizing_device" ON "public"."web_sessions" USING "btree" ("authorizing_device_id");



CREATE INDEX "idx_web_sessions_expires_at" ON "public"."web_sessions" USING "btree" ("expires_at");



CREATE INDEX "idx_web_sessions_permission" ON "public"."web_sessions" USING "btree" ("permission");



CREATE INDEX "idx_web_sessions_session_token_hash" ON "public"."web_sessions" USING "btree" ("session_token_hash");



CREATE INDEX "idx_web_sessions_status" ON "public"."web_sessions" USING "btree" ("status");



CREATE INDEX "idx_web_sessions_user_id" ON "public"."web_sessions" USING "btree" ("user_id");



CREATE INDEX "idx_web_sessions_user_status" ON "public"."web_sessions" USING "btree" ("user_id", "status");



CREATE OR REPLACE TRIGGER "trigger_prevent_web_device_trust" BEFORE INSERT OR UPDATE OF "is_trusted" ON "public"."devices" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_web_device_trust"();



ALTER TABLE ONLY "public"."account_delete_tokens"
    ADD CONSTRAINT "account_delete_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_customers"
    ADD CONSTRAINT "billing_customers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_gateway_customer_id_fkey" FOREIGN KEY ("gateway_customer_id") REFERENCES "public"."billing_customers"("gateway_customer_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_gateway_price_id_fkey" FOREIGN KEY ("gateway_price_id") REFERENCES "public"."billing_prices"("gateway_price_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_gateway_product_id_fkey" FOREIGN KEY ("gateway_product_id") REFERENCES "public"."billing_products"("gateway_product_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_one_time_payments"
    ADD CONSTRAINT "billing_one_time_payments_gateway_customer_id_fkey" FOREIGN KEY ("gateway_customer_id") REFERENCES "public"."billing_customers"("gateway_customer_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_one_time_payments"
    ADD CONSTRAINT "billing_one_time_payments_gateway_invoice_id_fkey" FOREIGN KEY ("gateway_invoice_id") REFERENCES "public"."billing_invoices"("gateway_invoice_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_one_time_payments"
    ADD CONSTRAINT "billing_one_time_payments_gateway_price_id_fkey" FOREIGN KEY ("gateway_price_id") REFERENCES "public"."billing_prices"("gateway_price_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_one_time_payments"
    ADD CONSTRAINT "billing_one_time_payments_gateway_product_id_fkey" FOREIGN KEY ("gateway_product_id") REFERENCES "public"."billing_products"("gateway_product_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_payment_methods"
    ADD CONSTRAINT "billing_payment_methods_gateway_customer_id_fkey" FOREIGN KEY ("gateway_customer_id") REFERENCES "public"."billing_customers"("gateway_customer_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_prices"
    ADD CONSTRAINT "billing_prices_gateway_product_id_fkey" FOREIGN KEY ("gateway_product_id") REFERENCES "public"."billing_products"("gateway_product_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_subscriptions"
    ADD CONSTRAINT "billing_subscriptions_gateway_customer_id_fkey" FOREIGN KEY ("gateway_customer_id") REFERENCES "public"."billing_customers"("gateway_customer_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_subscriptions"
    ADD CONSTRAINT "billing_subscriptions_gateway_price_id_fkey" FOREIGN KEY ("gateway_price_id") REFERENCES "public"."billing_prices"("gateway_price_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_subscriptions"
    ADD CONSTRAINT "billing_subscriptions_gateway_product_id_fkey" FOREIGN KEY ("gateway_product_id") REFERENCES "public"."billing_products"("gateway_product_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_usage_logs"
    ADD CONSTRAINT "billing_usage_logs_gateway_customer_id_fkey" FOREIGN KEY ("gateway_customer_id") REFERENCES "public"."billing_customers"("gateway_customer_id");



ALTER TABLE ONLY "public"."billing_volume_tiers"
    ADD CONSTRAINT "billing_volume_tiers_gateway_price_id_fkey" FOREIGN KEY ("gateway_price_id") REFERENCES "public"."billing_prices"("gateway_price_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claude_runs"
    ADD CONSTRAINT "claude_runs_coding_session_id_fkey" FOREIGN KEY ("coding_session_id") REFERENCES "public"."agent_coding_sessions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."claude_runs"
    ADD CONSTRAINT "claude_runs_executor_device_id_fkey" FOREIGN KEY ("executor_device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claude_runs"
    ADD CONSTRAINT "claude_runs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."agent_coding_session_secrets"
    ADD CONSTRAINT "coding_session_secrets_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."agent_coding_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."agent_coding_sessions"
    ADD CONSTRAINT "coding_sessions_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."agent_coding_sessions"
    ADD CONSTRAINT "coding_sessions_repository_id_fkey" FOREIGN KEY ("repository_id") REFERENCES "public"."repositories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."agent_coding_sessions"
    ADD CONSTRAINT "coding_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."agent_coding_session_messages"
    ADD CONSTRAINT "conversation_events_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."agent_coding_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_pairwise_secrets"
    ADD CONSTRAINT "device_pairwise_secrets_device_a_id_fkey" FOREIGN KEY ("device_a_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_pairwise_secrets"
    ADD CONSTRAINT "device_pairwise_secrets_device_b_id_fkey" FOREIGN KEY ("device_b_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_pairwise_secrets"
    ADD CONSTRAINT "device_pairwise_secrets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_trust_graph"
    ADD CONSTRAINT "device_trust_graph_grantee_device_id_fkey" FOREIGN KEY ("grantee_device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_trust_graph"
    ADD CONSTRAINT "device_trust_graph_grantor_device_id_fkey" FOREIGN KEY ("grantor_device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_trust_graph"
    ADD CONSTRAINT "device_trust_graph_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."devices"
    ADD CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."live_activity_tokens"
    ADD CONSTRAINT "live_activity_tokens_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_blog_author_posts"
    ADD CONSTRAINT "marketing_blog_author_posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."marketing_author_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_blog_author_posts"
    ADD CONSTRAINT "marketing_blog_author_posts_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."marketing_blog_posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_blog_post_tags_relationship"
    ADD CONSTRAINT "marketing_blog_post_tags_relationship_blog_post_id_fkey" FOREIGN KEY ("blog_post_id") REFERENCES "public"."marketing_blog_posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_blog_post_tags_relationship"
    ADD CONSTRAINT "marketing_blog_post_tags_relationship_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."marketing_tags"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_changelog_author_relationship"
    ADD CONSTRAINT "marketing_changelog_author_relationship_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."marketing_author_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_changelog_author_relationship"
    ADD CONSTRAINT "marketing_changelog_author_relationship_changelog_id_fkey" FOREIGN KEY ("changelog_id") REFERENCES "public"."marketing_changelog"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_board_subscriptions"
    ADD CONSTRAINT "marketing_feedback_board_subscriptions_board_id_fkey" FOREIGN KEY ("board_id") REFERENCES "public"."marketing_feedback_boards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_board_subscriptions"
    ADD CONSTRAINT "marketing_feedback_board_subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_boards"
    ADD CONSTRAINT "marketing_feedback_boards_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_comment_reactions"
    ADD CONSTRAINT "marketing_feedback_comment_reactions_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."marketing_feedback_comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_comment_reactions"
    ADD CONSTRAINT "marketing_feedback_comment_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_comments"
    ADD CONSTRAINT "marketing_feedback_comments_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."marketing_feedback_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_comments"
    ADD CONSTRAINT "marketing_feedback_comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_thread_reactions"
    ADD CONSTRAINT "marketing_feedback_thread_reactions_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."marketing_feedback_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_thread_reactions"
    ADD CONSTRAINT "marketing_feedback_thread_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_thread_subscriptions"
    ADD CONSTRAINT "marketing_feedback_thread_subscriptions_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."marketing_feedback_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_thread_subscriptions"
    ADD CONSTRAINT "marketing_feedback_thread_subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_threads"
    ADD CONSTRAINT "marketing_feedback_threads_board_id_fkey" FOREIGN KEY ("board_id") REFERENCES "public"."marketing_feedback_boards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."marketing_feedback_threads"
    ADD CONSTRAINT "marketing_feedback_threads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pairing_tokens"
    ADD CONSTRAINT "pairing_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repositories"
    ADD CONSTRAINT "repositories_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repositories"
    ADD CONSTRAINT "repositories_parent_repository_id_fkey" FOREIGN KEY ("parent_repository_id") REFERENCES "public"."repositories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repositories"
    ADD CONSTRAINT "repositories_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."run_viewers"
    ADD CONSTRAINT "run_viewers_run_id_fkey" FOREIGN KEY ("run_id") REFERENCES "public"."claude_runs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."run_viewers"
    ADD CONSTRAINT "run_viewers_viewer_device_id_fkey" FOREIGN KEY ("viewer_device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."run_viewers"
    ADD CONSTRAINT "run_viewers_viewer_web_session_id_fkey" FOREIGN KEY ("viewer_web_session_id") REFERENCES "public"."web_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_api_keys"
    ADD CONSTRAINT "user_api_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_application_settings"
    ADD CONSTRAINT "user_application_settings_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."web_sessions"
    ADD CONSTRAINT "web_sessions_authorizing_device_id_fkey" FOREIGN KEY ("authorizing_device_id") REFERENCES "public"."devices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."web_sessions"
    ADD CONSTRAINT "web_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



CREATE POLICY "Admins can update settings" ON "public"."app_settings" FOR UPDATE TO "authenticated" USING ("public"."is_application_admin"("auth"."uid"())) WITH CHECK ("public"."is_application_admin"("auth"."uid"()));



CREATE POLICY "Admins can view settings" ON "public"."app_settings" FOR SELECT TO "authenticated" USING ("public"."is_application_admin"("auth"."uid"()));



CREATE POLICY "All authenticated users can request deletion" ON "public"."account_delete_tokens" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "All supabase auth admin can view" ON "public"."user_roles" FOR SELECT TO "supabase_auth_admin" USING (true);



CREATE POLICY "Allow auth admin to read user roles" ON "public"."user_roles" FOR SELECT TO "supabase_auth_admin" USING (true);



CREATE POLICY "Authenticated users can create feedback comments" ON "public"."marketing_feedback_comments" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Authenticated users can create feedback threads" ON "public"."marketing_feedback_threads" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Authenticated users can delete their own feedback comments" ON "public"."marketing_feedback_comments" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Authenticated users can delete their own feedback threads" ON "public"."marketing_feedback_threads" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Authenticated users can update their own feedback comments" ON "public"."marketing_feedback_comments" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Authenticated users can update their own feedback threads" ON "public"."marketing_feedback_threads" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Authenticated users can view feedback comments" ON "public"."marketing_feedback_comments" FOR SELECT USING (("moderator_hold_category" IS NULL));



CREATE POLICY "Authenticated users can view feedback threads if they are added" ON "public"."marketing_feedback_threads" FOR SELECT USING ((("added_to_roadmap" = true) OR ("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("open_for_public_discussion" = true) OR ("moderator_hold_category" IS NULL)));



CREATE POLICY "Author profiles are visible to everyone" ON "public"."marketing_author_profiles" FOR SELECT USING (true);



CREATE POLICY "Blog post author relationships are visible to everyone" ON "public"."marketing_blog_author_posts" FOR SELECT USING (true);



CREATE POLICY "Blog post tags relationship is visible to everyone" ON "public"."marketing_blog_post_tags_relationship" FOR SELECT USING (true);



CREATE POLICY "Changelog author relationship is visible to everyone" ON "public"."marketing_changelog_author_relationship" FOR SELECT USING (true);



CREATE POLICY "Everyone can view billing_prices" ON "public"."billing_prices" FOR SELECT USING (true);



CREATE POLICY "Everyone can view billing_volume_tiers" ON "public"."billing_volume_tiers" FOR SELECT USING (true);



CREATE POLICY "Everyone can view plans" ON "public"."billing_products" FOR SELECT USING (true);



CREATE POLICY "Everyone can view user profile" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Only admins can delete boards" ON "public"."marketing_feedback_boards" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Only admins can insert boards" ON "public"."marketing_feedback_boards" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Only admins can update boards" ON "public"."marketing_feedback_boards" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Only published changelogs are visible to everyone" ON "public"."marketing_changelog" FOR SELECT USING (("status" = 'published'::"public"."marketing_changelog_status"));



CREATE POLICY "Only the own user can update it" ON "public"."user_profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Public boards are viewable by everyone" ON "public"."marketing_feedback_boards" FOR SELECT USING (("is_active" = true));



CREATE POLICY "Published blog posts are visible to everyone" ON "public"."marketing_blog_posts" FOR SELECT USING (("status" = 'published'::"public"."marketing_blog_post_status"));



CREATE POLICY "Run owners can add viewers" ON "public"."run_viewers" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."claude_runs" "cr"
  WHERE (("cr"."id" = "run_viewers"."run_id") AND ("cr"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Run owners can remove viewers" ON "public"."run_viewers" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."claude_runs" "cr"
  WHERE (("cr"."id" = "run_viewers"."run_id") AND ("cr"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Run owners can update viewers" ON "public"."run_viewers" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."claude_runs" "cr"
  WHERE (("cr"."id" = "run_viewers"."run_id") AND ("cr"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Run owners can view their run viewers" ON "public"."run_viewers" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."claude_runs" "cr"
  WHERE (("cr"."id" = "run_viewers"."run_id") AND ("cr"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Tags are visible to everyone" ON "public"."marketing_tags" FOR SELECT USING (true);



CREATE POLICY "User can insert their own keys" ON "public"."user_api_keys" FOR INSERT WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "User can only delete their own deletion token" ON "public"."account_delete_tokens" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "User can only read their own deletion token" ON "public"."account_delete_tokens" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "User can only update their own deletion token" ON "public"."account_delete_tokens" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "User can select their own keys" ON "public"."user_api_keys" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "User can update their own keys" ON "public"."user_api_keys" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users can add their own comment reactions" ON "public"."marketing_feedback_comment_reactions" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can add their own reactions" ON "public"."marketing_feedback_thread_reactions" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create own pairing tokens" ON "public"."pairing_tokens" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create pairwise secrets for their devices" ON "public"."device_pairwise_secrets" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can create runs from their devices" ON "public"."claude_runs" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM "public"."devices"
  WHERE (("devices"."id" = "claude_runs"."executor_device_id") AND ("devices"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("devices"."is_active" = true))))));



CREATE POLICY "Users can create their own web sessions" ON "public"."web_sessions" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can create trust relationships for their devices" ON "public"."device_trust_graph" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete own device activity tokens" ON "public"."live_activity_tokens" FOR DELETE USING (("device_id" IN ( SELECT "devices"."id"
   FROM "public"."devices"
  WHERE ("devices"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can delete own pairing tokens" ON "public"."pairing_tokens" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own agent coding sessions" ON "public"."agent_coding_sessions" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their own devices" ON "public"."devices" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their own pairwise secrets" ON "public"."device_pairwise_secrets" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their own repositories" ON "public"."repositories" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their own runs" ON "public"."claude_runs" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their own trust relationships" ON "public"."device_trust_graph" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their own web sessions" ON "public"."web_sessions" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can insert own device activity tokens" ON "public"."live_activity_tokens" FOR INSERT WITH CHECK (("device_id" IN ( SELECT "devices"."id"
   FROM "public"."devices"
  WHERE ("devices"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can insert their own agent coding sessions" ON "public"."agent_coding_sessions" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can insert their own devices" ON "public"."devices" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can insert their own repositories" ON "public"."repositories" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can manage their own board subscriptions" ON "public"."marketing_feedback_board_subscriptions" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage their own thread subscriptions" ON "public"."marketing_feedback_thread_subscriptions" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can perform all operations on their own chats" ON "public"."chats" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can remove their own comment reactions" ON "public"."marketing_feedback_comment_reactions" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can remove their own reactions" ON "public"."marketing_feedback_thread_reactions" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own device activity tokens" ON "public"."live_activity_tokens" FOR UPDATE USING (("device_id" IN ( SELECT "devices"."id"
   FROM "public"."devices"
  WHERE ("devices"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can update own pairing tokens" ON "public"."pairing_tokens" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own agent coding sessions" ON "public"."agent_coding_sessions" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own devices" ON "public"."devices" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own notifications" ON "public"."user_notifications" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users can update their own pairwise secrets" ON "public"."device_pairwise_secrets" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own repositories" ON "public"."repositories" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own runs" ON "public"."claude_runs" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own settings" ON "public"."user_settings" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users can update their own trust relationships" ON "public"."device_trust_graph" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own web sessions" ON "public"."web_sessions" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view all comment reactions" ON "public"."marketing_feedback_comment_reactions" FOR SELECT USING (true);



CREATE POLICY "Users can view all thread reactions" ON "public"."marketing_feedback_thread_reactions" FOR SELECT USING (true);



CREATE POLICY "Users can view own device activity tokens" ON "public"."live_activity_tokens" FOR SELECT USING (("device_id" IN ( SELECT "devices"."id"
   FROM "public"."devices"
  WHERE ("devices"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can view own pairing tokens" ON "public"."pairing_tokens" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own agent coding session messages" ON "public"."agent_coding_session_messages" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."agent_coding_sessions"
  WHERE (("agent_coding_sessions"."id" = "agent_coding_session_messages"."session_id") AND ("agent_coding_sessions"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Users can view their own agent coding session secrets" ON "public"."agent_coding_session_secrets" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."agent_coding_sessions"
  WHERE (("agent_coding_sessions"."id" = "agent_coding_session_secrets"."session_id") AND ("agent_coding_sessions"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Users can view their own agent coding sessions" ON "public"."agent_coding_sessions" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own application settings" ON "public"."user_application_settings" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users can view their own billing customer" ON "public"."billing_customers" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own board subscriptions" ON "public"."marketing_feedback_board_subscriptions" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own devices" ON "public"."devices" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own invoices" ON "public"."billing_invoices" FOR SELECT USING (("public"."get_customer_user_id"("gateway_customer_id") = "auth"."uid"()));



CREATE POLICY "Users can view their own one time payments" ON "public"."billing_one_time_payments" FOR SELECT USING (("public"."get_customer_user_id"("gateway_customer_id") = "auth"."uid"()));



CREATE POLICY "Users can view their own pairwise secrets" ON "public"."device_pairwise_secrets" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own payment methods" ON "public"."billing_payment_methods" FOR SELECT USING (("public"."get_customer_user_id"("gateway_customer_id") = "auth"."uid"()));



CREATE POLICY "Users can view their own repositories" ON "public"."repositories" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own runs" ON "public"."claude_runs" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own settings" ON "public"."user_settings" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users can view their own subscriptions" ON "public"."billing_subscriptions" FOR SELECT USING (("public"."get_customer_user_id"("gateway_customer_id") = "auth"."uid"()));



CREATE POLICY "Users can view their own thread subscriptions" ON "public"."marketing_feedback_thread_subscriptions" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own trust relationships" ON "public"."device_trust_graph" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own usage logs" ON "public"."billing_usage_logs" FOR SELECT USING (("public"."get_customer_user_id"("gateway_customer_id") = "auth"."uid"()));



CREATE POLICY "Users can view their own web sessions" ON "public"."web_sessions" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."account_delete_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_coding_session_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_coding_session_secrets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_coding_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "any_user_can_create_notification" ON "public"."user_notifications" FOR INSERT TO "authenticated" WITH CHECK (true);



ALTER TABLE "public"."app_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_one_time_payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_payment_methods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_prices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_usage_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_volume_tiers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."claude_runs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_pairwise_secrets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_trust_graph" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."devices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."live_activity_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_author_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_blog_author_posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_blog_post_tags_relationship" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_blog_posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_changelog" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_changelog_author_relationship" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_feedback_board_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_feedback_boards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_feedback_comment_reactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_feedback_comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_feedback_thread_reactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_feedback_thread_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_feedback_threads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."marketing_tags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "only_user_can_delete_their_notification" ON "public"."user_notifications" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "only_user_can_read_their_own_notification" ON "public"."user_notifications" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "only_user_can_update_their_notification" ON "public"."user_notifications" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."pairing_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."repositories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."run_viewers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_api_keys" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_application_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."web_sessions" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."agent_coding_sessions";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."claude_runs";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."run_viewers";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."user_notifications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."web_sessions";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
GRANT USAGE ON SCHEMA "public" TO "supabase_auth_admin";































































































































































GRANT ALL ON FUNCTION "public"."app_admin_get_projects_created_per_month"() TO "service_role";



GRANT ALL ON FUNCTION "public"."app_admin_get_recent_30_day_signin_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."app_admin_get_total_organization_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."app_admin_get_total_project_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."app_admin_get_total_user_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."app_admin_get_user_id_by_email"("emailarg" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."app_admin_get_users_created_per_month"() TO "service_role";



GRANT ALL ON FUNCTION "public"."authorize_web_session"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."authorize_web_session"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."authorize_web_session"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."authorize_web_session_v2"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text", "p_permission" "public"."web_session_permission", "p_session_ttl_seconds" integer, "p_max_idle_seconds" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."authorize_web_session_v2"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text", "p_permission" "public"."web_session_permission", "p_session_ttl_seconds" integer, "p_max_idle_seconds" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."authorize_web_session_v2"("p_session_id" "uuid", "p_device_id" "uuid", "p_encrypted_session_key" "text", "p_responder_public_key" "text", "p_permission" "public"."web_session_permission", "p_session_ttl_seconds" integer, "p_max_idle_seconds" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_if_authenticated_user_owns_email"("email" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_expired_web_sessions"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_expired_web_sessions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_expired_web_sessions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_stale_claude_runs"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_stale_claude_runs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_stale_claude_runs"() TO "service_role";



GRANT ALL ON FUNCTION "public"."custom_access_token_hook"("event" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."custom_access_token_hook"("event" "jsonb") TO "supabase_auth_admin";



GRANT ALL ON FUNCTION "public"."decrement_credits"("org_id" "uuid", "amount" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."expire_old_pairing_tokens"() TO "anon";
GRANT ALL ON FUNCTION "public"."expire_old_pairing_tokens"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."expire_old_pairing_tokens"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_user_id"("p_gateway_customer_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_user_id"("p_gateway_customer_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_user_id"("p_gateway_customer_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_device_pair_id"("p_device_id_1" "uuid", "p_device_id_2" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_device_pair_id"("p_device_id_1" "uuid", "p_device_id_2" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_device_pair_id"("p_device_id_1" "uuid", "p_device_id_2" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_device_trust_chain"("p_device_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_device_trust_chain"("p_device_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_device_trust_chain"("p_device_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_run_active_viewers"("p_run_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_run_active_viewers"("p_run_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_run_active_viewers"("p_run_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_devices_with_trust"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_devices_with_trust"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_devices_with_trust"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_auth_user_created"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_create_welcome_notification"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_application_admin"("user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_application_admin"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_application_admin"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_device_trusted"("p_user_id" "uuid", "p_device_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_device_trusted"("p_user_id" "uuid", "p_device_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_device_trusted"("p_user_id" "uuid", "p_device_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_web_session_valid"("p_session_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_web_session_valid"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_web_session_valid"("p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") FROM PUBLIC;



GRANT ALL ON FUNCTION "public"."prevent_web_device_trust"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_web_device_trust"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_web_device_trust"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") FROM PUBLIC;



GRANT ALL ON FUNCTION "public"."revoke_device_trust"("p_device_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."revoke_device_trust"("p_device_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_device_trust"("p_device_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."revoke_web_session"("p_session_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."revoke_web_session"("p_session_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_web_session"("p_session_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_web_session"("p_session_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."touch_web_session"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_web_session"("p_session_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_user_application_settings_email"() TO "service_role";


















GRANT ALL ON TABLE "public"."account_delete_tokens" TO "anon";
GRANT ALL ON TABLE "public"."account_delete_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."account_delete_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."agent_coding_session_messages" TO "anon";
GRANT ALL ON TABLE "public"."agent_coding_session_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_coding_session_messages" TO "service_role";



GRANT ALL ON TABLE "public"."agent_coding_session_secrets" TO "anon";
GRANT ALL ON TABLE "public"."agent_coding_session_secrets" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_coding_session_secrets" TO "service_role";



GRANT ALL ON TABLE "public"."agent_coding_sessions" TO "anon";
GRANT ALL ON TABLE "public"."agent_coding_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_coding_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."app_settings" TO "anon";
GRANT ALL ON TABLE "public"."app_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."app_settings" TO "service_role";



GRANT ALL ON TABLE "public"."billing_customers" TO "anon";
GRANT ALL ON TABLE "public"."billing_customers" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_customers" TO "service_role";



GRANT ALL ON TABLE "public"."billing_invoices" TO "anon";
GRANT ALL ON TABLE "public"."billing_invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_invoices" TO "service_role";



GRANT ALL ON TABLE "public"."billing_one_time_payments" TO "anon";
GRANT ALL ON TABLE "public"."billing_one_time_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_one_time_payments" TO "service_role";



GRANT ALL ON TABLE "public"."billing_payment_methods" TO "anon";
GRANT ALL ON TABLE "public"."billing_payment_methods" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_payment_methods" TO "service_role";



GRANT ALL ON TABLE "public"."billing_prices" TO "anon";
GRANT ALL ON TABLE "public"."billing_prices" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_prices" TO "service_role";



GRANT ALL ON TABLE "public"."billing_products" TO "anon";
GRANT ALL ON TABLE "public"."billing_products" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_products" TO "service_role";



GRANT ALL ON TABLE "public"."billing_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."billing_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."billing_usage_logs" TO "anon";
GRANT ALL ON TABLE "public"."billing_usage_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_usage_logs" TO "service_role";



GRANT ALL ON TABLE "public"."billing_volume_tiers" TO "anon";
GRANT ALL ON TABLE "public"."billing_volume_tiers" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_volume_tiers" TO "service_role";



GRANT ALL ON TABLE "public"."chats" TO "anon";
GRANT ALL ON TABLE "public"."chats" TO "authenticated";
GRANT ALL ON TABLE "public"."chats" TO "service_role";



GRANT ALL ON TABLE "public"."claude_runs" TO "anon";
GRANT ALL ON TABLE "public"."claude_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."claude_runs" TO "service_role";



GRANT ALL ON SEQUENCE "public"."coding_session_secrets_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."coding_session_secrets_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."coding_session_secrets_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."conversation_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."conversation_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."conversation_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."device_pairwise_secrets" TO "anon";
GRANT ALL ON TABLE "public"."device_pairwise_secrets" TO "authenticated";
GRANT ALL ON TABLE "public"."device_pairwise_secrets" TO "service_role";



GRANT ALL ON TABLE "public"."device_trust_graph" TO "anon";
GRANT ALL ON TABLE "public"."device_trust_graph" TO "authenticated";
GRANT ALL ON TABLE "public"."device_trust_graph" TO "service_role";



GRANT ALL ON TABLE "public"."devices" TO "anon";
GRANT ALL ON TABLE "public"."devices" TO "authenticated";
GRANT ALL ON TABLE "public"."devices" TO "service_role";



GRANT ALL ON TABLE "public"."live_activity_tokens" TO "anon";
GRANT ALL ON TABLE "public"."live_activity_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."live_activity_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_author_profiles" TO "anon";
GRANT ALL ON TABLE "public"."marketing_author_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_author_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_blog_author_posts" TO "anon";
GRANT ALL ON TABLE "public"."marketing_blog_author_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_blog_author_posts" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_blog_post_tags_relationship" TO "anon";
GRANT ALL ON TABLE "public"."marketing_blog_post_tags_relationship" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_blog_post_tags_relationship" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_blog_posts" TO "anon";
GRANT ALL ON TABLE "public"."marketing_blog_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_blog_posts" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_changelog" TO "anon";
GRANT ALL ON TABLE "public"."marketing_changelog" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_changelog" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_changelog_author_relationship" TO "anon";
GRANT ALL ON TABLE "public"."marketing_changelog_author_relationship" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_changelog_author_relationship" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_feedback_board_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."marketing_feedback_board_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_feedback_board_subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_feedback_boards" TO "anon";
GRANT ALL ON TABLE "public"."marketing_feedback_boards" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_feedback_boards" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_feedback_comment_reactions" TO "anon";
GRANT ALL ON TABLE "public"."marketing_feedback_comment_reactions" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_feedback_comment_reactions" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_feedback_comments" TO "anon";
GRANT ALL ON TABLE "public"."marketing_feedback_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_feedback_comments" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_feedback_thread_reactions" TO "anon";
GRANT ALL ON TABLE "public"."marketing_feedback_thread_reactions" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_feedback_thread_reactions" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_feedback_thread_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."marketing_feedback_thread_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_feedback_thread_subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_feedback_threads" TO "anon";
GRANT ALL ON TABLE "public"."marketing_feedback_threads" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_feedback_threads" TO "service_role";



GRANT ALL ON TABLE "public"."marketing_tags" TO "anon";
GRANT ALL ON TABLE "public"."marketing_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."marketing_tags" TO "service_role";



GRANT ALL ON TABLE "public"."pairing_tokens" TO "anon";
GRANT ALL ON TABLE "public"."pairing_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."pairing_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."repositories" TO "anon";
GRANT ALL ON TABLE "public"."repositories" TO "authenticated";
GRANT ALL ON TABLE "public"."repositories" TO "service_role";



GRANT ALL ON TABLE "public"."run_viewers" TO "anon";
GRANT ALL ON TABLE "public"."run_viewers" TO "authenticated";
GRANT ALL ON TABLE "public"."run_viewers" TO "service_role";



GRANT ALL ON TABLE "public"."user_api_keys" TO "anon";
GRANT ALL ON TABLE "public"."user_api_keys" TO "authenticated";
GRANT ALL ON TABLE "public"."user_api_keys" TO "service_role";



GRANT ALL ON TABLE "public"."user_application_settings" TO "anon";
GRANT ALL ON TABLE "public"."user_application_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."user_application_settings" TO "service_role";



GRANT ALL ON TABLE "public"."user_notifications" TO "anon";
GRANT ALL ON TABLE "public"."user_notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."user_notifications" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."user_roles" TO "service_role";
GRANT ALL ON TABLE "public"."user_roles" TO "supabase_auth_admin";



GRANT ALL ON TABLE "public"."user_settings" TO "anon";
GRANT ALL ON TABLE "public"."user_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."user_settings" TO "service_role";



GRANT ALL ON TABLE "public"."web_sessions" TO "anon";
GRANT ALL ON TABLE "public"."web_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."web_sessions" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
































--
-- Dumped schema changes for auth and storage
--

CREATE OR REPLACE TRIGGER "on_auth_user_created_create_profile" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_auth_user_created"();



CREATE OR REPLACE TRIGGER "on_auth_user_created_create_welcome_notification" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_create_welcome_notification"();



CREATE OR REPLACE TRIGGER "on_auth_user_email_updated" AFTER UPDATE OF "email" ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."update_user_application_settings_email"();



CREATE POLICY "Allow users to read their changelog assets" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'changelog-assets'::"text"));



CREATE POLICY "Allow users to read their openai images" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'openai-images'::"text"));



CREATE POLICY "Public Access for admin-blog " ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'admin-blog'::"text"));



CREATE POLICY "Public Access for marketing-assets" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'marketing-assets'::"text"));



CREATE POLICY "Public Access for public-assets 1plzjha_3" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'public-assets'::"text"));



CREATE POLICY "Users can manage their own private assets" ON "storage"."objects" TO "authenticated" USING ((("bucket_id" = 'user-assets'::"text") AND ((( SELECT ( SELECT "auth"."uid"() AS "uid") AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));



CREATE POLICY "Users can upload to their own public assets" ON "storage"."objects" WITH CHECK ((("bucket_id" = 'public-user-assets'::"text") AND ((( SELECT "auth"."uid"() AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));



CREATE POLICY "Users can view public assets of all users" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'public-user-assets'::"text"));



