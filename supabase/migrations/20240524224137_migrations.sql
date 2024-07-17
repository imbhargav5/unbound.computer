
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

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE TYPE "public"."app_admin_role" AS ENUM (
    'moderator',
    'admin',
    'super_admin'
);

ALTER TYPE "public"."app_admin_role" OWNER TO "postgres";

CREATE TYPE "public"."app_role" AS ENUM (
    'admin'
);

ALTER TYPE "public"."app_role" OWNER TO "postgres";

CREATE TYPE "public"."internal_blog_post_status" AS ENUM (
    'draft',
    'published'
);

ALTER TYPE "public"."internal_blog_post_status" OWNER TO "postgres";

CREATE TYPE "public"."internal_feedback_thread_priority" AS ENUM (
    'low',
    'medium',
    'high'
);

ALTER TYPE "public"."internal_feedback_thread_priority" OWNER TO "postgres";

CREATE TYPE "public"."internal_feedback_thread_status" AS ENUM (
    'open',
    'under_review',
    'planned',
    'closed',
    'in_progress',
    'completed'
);

ALTER TYPE "public"."internal_feedback_thread_status" OWNER TO "postgres";

CREATE TYPE "public"."internal_feedback_thread_type" AS ENUM (
    'bug',
    'feature_request',
    'general'
);

ALTER TYPE "public"."internal_feedback_thread_type" OWNER TO "postgres";

CREATE TYPE "public"."organization_join_invitation_link_status" AS ENUM (
    'active',
    'finished_accepted',
    'finished_declined',
    'inactive'
);

ALTER TYPE "public"."organization_join_invitation_link_status" OWNER TO "postgres";

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

CREATE TYPE "public"."project_status" AS ENUM (
    'draft',
    'pending_approval',
    'approved',
    'completed'
);

ALTER TYPE "public"."project_status" OWNER TO "postgres";

CREATE TYPE "public"."project_team_member_role" AS ENUM (
    'admin',
    'member',
    'readonly'
);

ALTER TYPE "public"."project_team_member_role" OWNER TO "postgres";

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

CREATE OR REPLACE FUNCTION "public"."app_admin_get_all_organizations"("search_query" character varying DEFAULT ''::character varying, "page" integer DEFAULT 1, "page_size" integer DEFAULT 20) RETURNS TABLE("id" "uuid", "created_at" timestamp with time zone, "title" character varying, "team_members_count" bigint, "owner_full_name" character varying, "owner_email" character varying, "credits" bigint)
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE <> 'service_role' THEN RAISE EXCEPTION 'Only service_role can execute this function';
END IF;
RETURN QUERY WITH team_member_counts AS (
  SELECT organization_id,
    COUNT(*) AS COUNT
  FROM public.organization_members
  GROUP BY organization_id
)
SELECT DISTINCT ON (p."id") p."id",
  p."created_at",
  p."title",
  tmc."count" AS "team_members_count",
  up."full_name" AS "owner_full_name",
  au."email" AS "owner_email",
  oc."credits"
FROM "public"."organizations" p
  INNER JOIN team_member_counts tmc ON p."id" = tmc."organization_id"
  INNER JOIN "public"."organization_members" owner_team_member ON p."id" = owner_team_member."organization_id"
  AND owner_team_member."member_role" = 'owner'::"public"."organization_member_role"
  INNER JOIN "public"."organization_credits" oc ON p."id" = oc."organization_id"
  INNER JOIN "public"."user_profiles" up ON owner_team_member."member_id" = up."id"
  INNER JOIN "auth"."users" au ON owner_team_member."member_id" = au."id"
WHERE p."id"::TEXT = search_query
  OR p."title" ILIKE '%' || search_query || '%'
  OR up."full_name" ILIKE '%' || search_query || '%'
  OR au."email" ILIKE '%' || search_query || '%'
ORDER BY p."id",
  p."created_at" DESC OFFSET (PAGE - 1) * page_size
LIMIT page_size;
END;
$$;

ALTER FUNCTION "public"."app_admin_get_all_organizations"("search_query" character varying, "page" integer, "page_size" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."app_admin_get_all_organizations_count"("search_query" character varying DEFAULT ''::character varying) RETURNS bigint
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'service_role',
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
RETURN (
  SELECT COUNT(*)
  FROM public.organizations p
    INNER JOIN public.organization_members owner_team_member ON p.id = owner_team_member.organization_id
    AND owner_team_member.member_role = 'owner'
    INNER JOIN public.user_profiles up ON owner_team_member.member_id = up.id
    LEFT JOIN public.user_roles ur ON owner_team_member.member_id = ur.user_id
    AND ur.role = 'admin'
  WHERE p.id::TEXT = search_query
    OR p.title ILIKE '%' || search_query || '%'
    OR up.full_name ILIKE '%' || search_query || '%'
    OR EXISTS (
      SELECT 1
      FROM auth.users au
      WHERE au.id = owner_team_member.member_id
        AND au.email ILIKE '%' || search_query || '%'
    )
);
END;
$$;

ALTER FUNCTION "public"."app_admin_get_all_organizations_count"("search_query" character varying) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."app_admin_get_all_users"("search_query" character varying DEFAULT ''::character varying, "page" integer DEFAULT 1, "page_size" integer DEFAULT 20) RETURNS TABLE("id" "uuid", "email" character varying, "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "full_name" character varying, "avatar_url" character varying, "is_app_admin" boolean, "confirmed_at" timestamp with time zone, "is_confirmed" boolean, "last_sign_in_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'service_role',
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
RETURN QUERY
SELECT u.id,
  u.email,
  u.created_at,
  u.updated_at,
  up.full_name,
  up.avatar_url,
  (ur.role IS NOT NULL) AS is_app_admin,
  u.confirmed_at,
  (u.confirmed_at IS NOT NULL) AS is_confirmed,
  u.last_sign_in_at
FROM auth.users AS u
  JOIN public.user_profiles up ON u.id = up.id
  LEFT JOIN public.user_roles ur ON u.id = ur.user_id
  AND ur.role = 'admin'
WHERE (
    u.id::TEXT = search_query
    OR u.email ILIKE '%' || search_query || '%'
    OR up.full_name ILIKE '%' || search_query || '%'
  )
ORDER BY u.created_at DESC OFFSET (PAGE - 1) * page_size
LIMIT page_size;
END;
$$;

ALTER FUNCTION "public"."app_admin_get_all_users"("search_query" character varying, "page" integer, "page_size" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."app_admin_get_all_users_count"("search_query" character varying DEFAULT ''::character varying) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE users_count integer;
BEGIN IF CURRENT_ROLE NOT IN (
  'service_role',
  'supabase_admin',
  'dashboard_user',
  'postgres'
) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;

SELECT COUNT(*) INTO users_count
FROM auth.users AS u
  JOIN public.user_profiles up ON u.id = up.id
  LEFT JOIN public.user_roles ur ON u.id = ur.user_id
  AND ur.role = 'admin'
WHERE (
    u.id::TEXT = search_query
    OR u.email ILIKE '%' || search_query || '%'
    OR up.full_name ILIKE '%' || search_query || '%'
  );

    RETURN users_count;
END;
$$;

ALTER FUNCTION "public"."app_admin_get_all_users_count"("search_query" character varying) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."app_admin_get_organizations_created_per_month"() RETURNS TABLE("month" "date", "number_of_organizations" integer)
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'service_role',
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
CREATE TEMPORARY TABLE temp_result (MONTH DATE, number_of_organizations INTEGER) ON COMMIT DROP;

  WITH date_series AS (
  SELECT DATE_TRUNC('MONTH', dd)::DATE AS MONTH
  FROM generate_series(
      DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '1 YEAR'),
      DATE_TRUNC('MONTH', CURRENT_DATE),
      '1 MONTH'::INTERVAL
    ) dd
),
organization_counts AS (
  SELECT DATE_TRUNC('MONTH', created_at)::DATE AS MONTH,
    COUNT(*) AS organization_count
  FROM public.organizations
  WHERE created_at >= CURRENT_DATE - INTERVAL '1 YEAR'
  GROUP BY MONTH
)
INSERT INTO temp_result
SELECT date_series.month,
  COALESCE(organization_counts.organization_count, 0)
FROM date_series
  LEFT JOIN organization_counts ON date_series.month = organization_counts.month
ORDER BY date_series.month;

  RETURN QUERY
SELECT *
FROM temp_result;
END;
$$;

ALTER FUNCTION "public"."app_admin_get_organizations_created_per_month"() OWNER TO "postgres";

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

CREATE OR REPLACE FUNCTION "public"."check_if_user_is_app_admin"("user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ -- Begin the function
  BEGIN -- Check if the given user ID exists in the app_admins table
  -- Return true if the user is a super admin
  RETURN EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = user_id
      AND auth.users.is_super_admin = TRUE
  );
END;
$$;

ALTER FUNCTION "public"."check_if_user_is_app_admin"("user_id" "uuid") OWNER TO "postgres";

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

CREATE OR REPLACE FUNCTION "public"."get_all_app_admins"() RETURNS TABLE("user_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN RETURN QUERY
SELECT auth.users.id
FROM auth.users
WHERE auth.users.is_super_admin = TRUE;
END;
$$;

ALTER FUNCTION "public"."get_all_app_admins"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_invited_organizations_for_user_v2"("user_id" "uuid", "user_email" character varying) RETURNS TABLE("organization_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN IF (user_id IS NULL)
  AND (
    user_email IS NULL
    OR user_email = ''
  ) THEN RETURN QUERY
SELECT id
FROM organizations
WHERE 1 = 0;
END IF;
RETURN QUERY
SELECT o.id AS organization_id
FROM organizations o
  JOIN organization_join_invitations oti ON o.id = oti.organization_id
WHERE (
    (
      (
        (
          oti.invitee_user_email = user_email
          OR oti.invitee_user_email ilike concat('%', user_email, '%')
        )
      )
      OR (oti.invitee_user_id = user_id)
    )
    AND (oti.status = 'active')
  );
END;
$$;

ALTER FUNCTION "public"."get_invited_organizations_for_user_v2"("user_id" "uuid", "user_email" character varying) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_organization_admin_ids"("organization_id" "uuid") RETURNS TABLE("member_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$ BEGIN -- This function returns the member_id column for all rows in the organization_members table
RETURN QUERY
SELECT organization_members.member_id
FROM organization_members
WHERE organization_members.organization_id = $1
  AND (
    member_role = 'admin'
    OR member_role = 'owner'
  );
END;
$_$;

ALTER FUNCTION "public"."get_organization_admin_ids"("organization_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_organization_id_by_team_id"("p_id" integer) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_organization_id UUID;
BEGIN
SELECT organization_id INTO v_organization_id
FROM teams
WHERE id = p_id;
RETURN v_organization_id;
EXCEPTION
WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'No organization found for the provided id: %',
p_id;
END;
$$;

ALTER FUNCTION "public"."get_organization_id_by_team_id"("p_id" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_organization_id_for_project_id"("project_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE org_id UUID;
BEGIN
SELECT p.organization_id INTO org_id
FROM projects p
WHERE p.id = project_id;
RETURN org_id;
END;
$$;

ALTER FUNCTION "public"."get_organization_id_for_project_id"("project_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_organization_member_ids"("organization_id" "uuid") RETURNS TABLE("member_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$ BEGIN -- This function returns the member_id column for all rows in the organization_members table
RETURN QUERY
SELECT organization_members.member_id
FROM organization_members
WHERE organization_members.organization_id = $1;
END;
$_$;

ALTER FUNCTION "public"."get_organization_member_ids"("organization_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_organizations_for_user"("user_id" "uuid") RETURNS TABLE("organization_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN RETURN QUERY
SELECT o.id AS organization_id
FROM organizations o
  JOIN organization_members ot ON o.id = ot.organization_id
WHERE ot.member_id = user_id;
END;
$$;

ALTER FUNCTION "public"."get_organizations_for_user"("user_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_team_id_for_project_id"("project_id" "uuid") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE team_id INT8;
BEGIN
SELECT p.team_id INTO team_id
FROM projects p
WHERE p.id = project_id;
RETURN team_id;
END;
$$;

ALTER FUNCTION "public"."get_team_id_for_project_id"("project_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_add_organization_member_after_invitation_accepted"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$BEGIN
INSERT INTO organization_members(member_id, member_role, organization_id)
VALUES (
    NEW.invitee_user_id,
    NEW.invitee_organization_role,
    NEW.organization_id
  );
RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."handle_add_organization_member_after_invitation_accepted"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_auth_user_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN
INSERT INTO public.user_profiles (id)
VALUES (NEW.id);
INSERT INTO public.user_private_info (id)
VALUES (NEW.id);
RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."handle_auth_user_created"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_create_welcome_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN
INSERT INTO public.user_notifications (user_id, payload)
VALUES (NEW.id, '{ "type": "welcome" }'::JSONB);
RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."handle_create_welcome_notification"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_organization_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN
INSERT INTO public.organizations_private_info (id)
VALUES (NEW.id);
RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."handle_organization_created"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_organization_created_add_credits"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN
INSERT INTO public.organization_credits (organization_id)
VALUES (NEW.id);
RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."handle_organization_created_add_credits"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."increment_credits"("org_id" "uuid", "amount" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN -- Decrement the credits column by the specified amount
UPDATE organization_credits
SET credits = credits + amount
WHERE organization_id = org_id;
END;
$$;

ALTER FUNCTION "public"."increment_credits"("org_id" "uuid", "amount" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'service_role',
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;

INSERT INTO public.user_roles (user_id, role)
VALUES (user_id_arg, 'admin') ON CONFLICT (user_id, role) DO NOTHING;
END;
$$;

ALTER FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'service_role',
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only service_role, supabase_admin, dashboard_user, postgres can execute this function';
END IF;
DELETE FROM public.user_roles
WHERE user_id = user_id_arg
  AND role = 'admin';
END;
$$;

ALTER FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."set_default_user_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."set_default_user_id"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."account_delete_tokens" (
    "token" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL
);

ALTER TABLE "public"."account_delete_tokens" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."chats" (
    "id" "text" NOT NULL,
    "user_id" "uuid",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "project_id" "uuid" NOT NULL
);

ALTER TABLE "public"."chats" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."customers" (
    "stripe_customer_id" character varying NOT NULL,
    "organization_id" "uuid" NOT NULL
);

ALTER TABLE "public"."customers" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."internal_blog_author_posts" (
    "author_id" "uuid" NOT NULL,
    "post_id" "uuid" NOT NULL
);

ALTER TABLE "public"."internal_blog_author_posts" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."internal_blog_author_profiles" (
    "user_id" "uuid" NOT NULL,
    "display_name" character varying(255) NOT NULL,
    "bio" "text" NOT NULL,
    "avatar_url" character varying(255) NOT NULL,
    "website_url" character varying(255),
    "twitter_handle" character varying(255),
    "facebook_handle" character varying(255),
    "linkedin_handle" character varying(255),
    "instagram_handle" character varying(255),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE "public"."internal_blog_author_profiles" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."internal_blog_post_tags" (
    "id" integer NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text"
);

ALTER TABLE "public"."internal_blog_post_tags" OWNER TO "postgres";

ALTER TABLE "public"."internal_blog_post_tags" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."internal_blog_post_tags_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "public"."internal_blog_post_tags_relationship" (
    "blog_post_id" "uuid" NOT NULL,
    "tag_id" integer NOT NULL
);

ALTER TABLE "public"."internal_blog_post_tags_relationship" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."internal_blog_posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" character varying(255) NOT NULL,
    "title" character varying(255) NOT NULL,
    "summary" "text" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "is_featured" boolean DEFAULT false NOT NULL,
    "status" "public"."internal_blog_post_status" DEFAULT 'draft'::"public"."internal_blog_post_status" NOT NULL,
    "cover_image" character varying(255),
    "seo_data" "jsonb",
    "json_content" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);

ALTER TABLE "public"."internal_blog_posts" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."internal_changelog" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" character varying(255) NOT NULL,
    "changes" "text" NOT NULL,
    "user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "cover_image" "text"
);

ALTER TABLE "public"."internal_changelog" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."internal_feedback_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE "public"."internal_feedback_comments" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."internal_feedback_threads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" character varying(255) NOT NULL,
    "content" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "priority" "public"."internal_feedback_thread_priority" DEFAULT 'low'::"public"."internal_feedback_thread_priority" NOT NULL,
    "type" "public"."internal_feedback_thread_type" DEFAULT 'general'::"public"."internal_feedback_thread_type" NOT NULL,
    "status" "public"."internal_feedback_thread_status" DEFAULT 'open'::"public"."internal_feedback_thread_status" NOT NULL,
    "added_to_roadmap" boolean DEFAULT false NOT NULL,
    "open_for_public_discussion" boolean DEFAULT false NOT NULL,
    "is_publicly_visible" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."internal_feedback_threads" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."organization_credits" (
    "organization_id" "uuid" NOT NULL,
    "credits" bigint DEFAULT '12'::bigint NOT NULL
);

ALTER TABLE "public"."organization_credits" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."organization_join_invitations" (
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "inviter_user_id" "uuid" NOT NULL,
    "status" "public"."organization_join_invitation_link_status" DEFAULT 'active'::"public"."organization_join_invitation_link_status" NOT NULL,
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "invitee_user_email" character varying NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "invitee_organization_role" "public"."organization_member_role" DEFAULT 'member'::"public"."organization_member_role" NOT NULL,
    "invitee_user_id" "uuid"
);

ALTER TABLE "public"."organization_join_invitations" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."organization_members" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "member_id" "uuid" NOT NULL,
    "member_role" "public"."organization_member_role" NOT NULL,
    "organization_id" "uuid" NOT NULL
);

ALTER TABLE "public"."organization_members" OWNER TO "postgres";

ALTER TABLE "public"."organization_members" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."organization_members_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "title" character varying DEFAULT 'Test Organization'::character varying NOT NULL,
    "slug" character varying(255) DEFAULT ("gen_random_uuid"())::"text" NOT NULL
);

ALTER TABLE "public"."organizations" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."organizations_private_info" (
    "id" "uuid" NOT NULL,
    "billing_address" "json",
    "payment_method" "json"
);

ALTER TABLE "public"."organizations_private_info" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."prices" (
    "id" character varying NOT NULL,
    "product_id" character varying,
    "active" boolean,
    "description" character varying,
    "unit_amount" bigint,
    "currency" character varying,
    "type" "public"."pricing_type",
    "interval" "public"."pricing_plan_interval",
    "interval_count" bigint,
    "trial_period_days" bigint,
    "metadata" "jsonb"
);

ALTER TABLE "public"."prices" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" character varying NOT NULL,
    "active" boolean,
    "name" character varying,
    "description" character varying,
    "image" character varying,
    "metadata" "jsonb"
);

ALTER TABLE "public"."products" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."project_comments" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "text" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "in_reply_to" bigint,
    "project_id" "uuid" NOT NULL
);

ALTER TABLE "public"."project_comments" OWNER TO "postgres";

ALTER TABLE "public"."project_comments" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."project_comments_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "team_id" bigint,
    "project_status" "public"."project_status" DEFAULT 'draft'::"public"."project_status" NOT NULL,
    "slug" character varying(255) DEFAULT ("gen_random_uuid"())::"text" NOT NULL
);

ALTER TABLE "public"."projects" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" character varying NOT NULL,
    "status" "public"."subscription_status",
    "metadata" "json",
    "price_id" character varying,
    "quantity" bigint,
    "cancel_at_period_end" boolean,
    "created" timestamp with time zone NOT NULL,
    "current_period_start" timestamp with time zone NOT NULL,
    "current_period_end" timestamp with time zone NOT NULL,
    "ended_at" timestamp with time zone,
    "cancel_at" timestamp with time zone,
    "canceled_at" timestamp with time zone,
    "trial_start" timestamp with time zone,
    "trial_end" timestamp with time zone,
    "organization_id" "uuid"
);

ALTER TABLE "public"."subscriptions" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_api_keys" (
    "key_id" "text" NOT NULL,
    "masked_key" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "expires_at" timestamp with time zone,
    "is_revoked" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."user_api_keys" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_notifications" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "is_read" boolean DEFAULT false NOT NULL,
    "is_seen" boolean DEFAULT false NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE "public"."user_notifications" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_onboarding" (
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "accepted_terms" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."user_onboarding" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_private_info" (
    "id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "default_organization" "uuid"
);

ALTER TABLE "public"."user_private_info" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "full_name" character varying,
    "avatar_url" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."user_profiles" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."app_role" NOT NULL
);

ALTER TABLE "public"."user_roles" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_roles" IS 'Application roles for each user.';

ALTER TABLE "public"."user_roles" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_roles_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE ONLY "public"."account_delete_tokens"
    ADD CONSTRAINT "account_delete_tokens_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("stripe_customer_id", "organization_id");

ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_stripe_customer_id_key" UNIQUE ("stripe_customer_id");

ALTER TABLE ONLY "public"."internal_blog_author_posts"
    ADD CONSTRAINT "internal_blog_author_posts_pkey" PRIMARY KEY ("author_id", "post_id");

ALTER TABLE ONLY "public"."internal_blog_author_profiles"
    ADD CONSTRAINT "internal_blog_author_profiles_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."internal_blog_post_tags"
    ADD CONSTRAINT "internal_blog_post_tags_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."internal_blog_post_tags_relationship"
    ADD CONSTRAINT "internal_blog_post_tags_relationship_pkey" PRIMARY KEY ("blog_post_id", "tag_id");

ALTER TABLE ONLY "public"."internal_blog_posts"
    ADD CONSTRAINT "internal_blog_posts_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."internal_blog_posts"
    ADD CONSTRAINT "internal_blog_posts_slug_key" UNIQUE ("slug");

ALTER TABLE ONLY "public"."internal_changelog"
    ADD CONSTRAINT "internal_changelog_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."internal_feedback_comments"
    ADD CONSTRAINT "internal_feedback_comments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."internal_feedback_threads"
    ADD CONSTRAINT "internal_feedback_threads_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."organization_credits"
    ADD CONSTRAINT "organization_credits_pkey" PRIMARY KEY ("organization_id");

ALTER TABLE ONLY "public"."organization_join_invitations"
    ADD CONSTRAINT "organization_invitations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_slug_key" UNIQUE ("slug");

ALTER TABLE ONLY "public"."prices"
    ADD CONSTRAINT "price_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "product_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."project_comments"
    ADD CONSTRAINT "project_comments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."organizations_private_info"
    ADD CONSTRAINT "projects_private_info_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_slug_key" UNIQUE ("slug");

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscription_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_api_keys"
    ADD CONSTRAINT "user_api_keys_pkey" PRIMARY KEY ("key_id");

ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_onboarding"
    ADD CONSTRAINT "user_onboarding_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."user_private_info"
    ADD CONSTRAINT "user_private_info_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_role_key" UNIQUE ("user_id", "role");

CREATE INDEX "customers_organization_id_index" ON "public"."customers" USING "btree" ("organization_id");

CREATE INDEX "customers_stripe_customer_id_index" ON "public"."customers" USING "btree" ("stripe_customer_id");

CREATE INDEX "organization_join_invitations_invitee_user_email_idx" ON "public"."organization_join_invitations" USING "btree" ("invitee_user_email");

CREATE INDEX "organization_join_invitations_invitee_user_id_idx" ON "public"."organization_join_invitations" USING "btree" ("invitee_user_id");

CREATE INDEX "organization_join_invitations_inviter_user_id_idx" ON "public"."organization_join_invitations" USING "btree" ("inviter_user_id");

CREATE INDEX "organization_join_invitations_organization_id_idx" ON "public"."organization_join_invitations" USING "btree" ("organization_id");

CREATE INDEX "organization_join_invitations_status_idx" ON "public"."organization_join_invitations" USING "btree" ("status");

CREATE INDEX "organization_members_member_id_idx" ON "public"."organization_members" USING "btree" ("member_id");

CREATE INDEX "organization_members_member_role_idx" ON "public"."organization_members" USING "btree" ("member_role");

CREATE INDEX "organization_members_organization_id_idx" ON "public"."organization_members" USING "btree" ("organization_id");

CREATE INDEX "prices_active_idx" ON "public"."prices" USING "btree" ("active");

CREATE INDEX "prices_product_id_idx" ON "public"."prices" USING "btree" ("product_id");

CREATE INDEX "products_active_idx" ON "public"."products" USING "btree" ("active");

CREATE INDEX "project_comments_project_id_idx" ON "public"."project_comments" USING "btree" ("project_id");

CREATE INDEX "project_comments_user_id_idx" ON "public"."project_comments" USING "btree" ("user_id");

CREATE INDEX "subscriptions_organization_id_idx" ON "public"."subscriptions" USING "btree" ("organization_id");

CREATE INDEX "subscriptions_price_id_idx" ON "public"."subscriptions" USING "btree" ("price_id");

CREATE INDEX "subscriptions_status_idx" ON "public"."subscriptions" USING "btree" ("status");

CREATE INDEX "user_notifications_user_id_idx" ON "public"."user_notifications" USING "btree" ("user_id");

CREATE INDEX "user_private_info_default_organization_idx" ON "public"."user_private_info" USING "btree" ("default_organization");

CREATE INDEX "user_roles_user_id_idx" ON "public"."user_roles" USING "btree" ("user_id");

CREATE OR REPLACE TRIGGER "on_organization_created" AFTER INSERT ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."handle_organization_created"();

CREATE OR REPLACE TRIGGER "on_organization_created_credits" AFTER INSERT ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."handle_organization_created_add_credits"();

CREATE OR REPLACE TRIGGER "on_organization_invitation_accepted_trigger" AFTER UPDATE ON "public"."organization_join_invitations" FOR EACH ROW WHEN ((("old"."status" <> "new"."status") AND ("new"."status" = 'finished_accepted'::"public"."organization_join_invitation_link_status"))) EXECUTE FUNCTION "public"."handle_add_organization_member_after_invitation_accepted"();

CREATE OR REPLACE TRIGGER "set_user_id_before_insert" BEFORE INSERT ON "public"."chats" FOR EACH ROW EXECUTE FUNCTION "public"."set_default_user_id"();

ALTER TABLE ONLY "public"."account_delete_tokens"
    ADD CONSTRAINT "account_delete_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_blog_author_posts"
    ADD CONSTRAINT "internal_blog_author_posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."internal_blog_author_profiles"("user_id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_blog_author_posts"
    ADD CONSTRAINT "internal_blog_author_posts_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."internal_blog_posts"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_blog_author_profiles"
    ADD CONSTRAINT "internal_blog_author_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_blog_post_tags_relationship"
    ADD CONSTRAINT "internal_blog_post_tags_relationship_blog_post_id_fkey" FOREIGN KEY ("blog_post_id") REFERENCES "public"."internal_blog_posts"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_blog_post_tags_relationship"
    ADD CONSTRAINT "internal_blog_post_tags_relationship_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."internal_blog_post_tags"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_changelog"
    ADD CONSTRAINT "internal_changelog_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_feedback_comments"
    ADD CONSTRAINT "internal_feedback_comments_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."internal_feedback_threads"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_feedback_comments"
    ADD CONSTRAINT "internal_feedback_comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."internal_feedback_threads"
    ADD CONSTRAINT "internal_feedback_threads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."organization_credits"
    ADD CONSTRAINT "organization_credits_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."organization_join_invitations"
    ADD CONSTRAINT "organization_join_invitations_invitee_user_id_fkey" FOREIGN KEY ("invitee_user_id") REFERENCES "public"."user_profiles"("id");

ALTER TABLE ONLY "public"."organization_join_invitations"
    ADD CONSTRAINT "organization_join_invitations_inviter_user_id_fkey" FOREIGN KEY ("inviter_user_id") REFERENCES "public"."user_profiles"("id");

ALTER TABLE ONLY "public"."organization_join_invitations"
    ADD CONSTRAINT "organization_join_invitations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_member_id_fkey" FOREIGN KEY ("member_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."organizations_private_info"
    ADD CONSTRAINT "organizations_private_info_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."prices"
    ADD CONSTRAINT "prices_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");

ALTER TABLE ONLY "public"."project_comments"
    ADD CONSTRAINT "project_comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "public_chats_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_price_id_fkey" FOREIGN KEY ("price_id") REFERENCES "public"."prices"("id");

ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_onboarding"
    ADD CONSTRAINT "user_onboarding_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_private_info"
    ADD CONSTRAINT "user_private_info_default_organization_fkey" FOREIGN KEY ("default_organization") REFERENCES "public"."organizations"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."user_private_info"
    ADD CONSTRAINT "user_private_info_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;

CREATE POLICY "Active products are visible to everyone" ON "public"."products" FOR SELECT USING (("active" = true));

CREATE POLICY "All authenticated members can insert" ON "public"."projects" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "All authenticated users can create organizations" ON "public"."organizations" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "All authenticated users can request deletion" ON "public"."account_delete_tokens" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "All organization members can read organizations v2" ON "public"."organizations" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("organizations"."id") AS "get_organization_member_ids")));

CREATE POLICY "All organization members can update organizations" ON "public"."organizations" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("organizations"."id") AS "get_organization_member_ids")));

CREATE POLICY "All organization members of a project can make project comments" ON "public"."project_comments" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("public"."get_organization_id_for_project_id"("project_comments"."project_id")) AS "get_organization_member_ids")));

CREATE POLICY "All organization members of a project can read project comments" ON "public"."project_comments" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("public"."get_organization_id_for_project_id"("project_comments"."project_id")) AS "get_organization_member_ids")));

CREATE POLICY "Allow  any to read admin blog author posts" ON "public"."internal_blog_author_posts" FOR SELECT USING (true);

CREATE POLICY "Allow anyone to read admin blog author profiles" ON "public"."internal_blog_author_profiles" FOR SELECT USING (true);

CREATE POLICY "Allow anyone to read admin blog post tags" ON "public"."internal_blog_post_tags" FOR SELECT USING (true);

CREATE POLICY "Allow anyone to read admin blog posts" ON "public"."internal_blog_posts" FOR SELECT USING (true);

CREATE POLICY "Allow anyone to read admin blog tag relationships" ON "public"."internal_blog_post_tags_relationship" FOR SELECT USING (true);

CREATE POLICY "Allow anyone to read changelog" ON "public"."internal_changelog" FOR SELECT USING (true);

CREATE POLICY "Allow auth admin to read user roles" ON "public"."user_roles" FOR SELECT TO "supabase_auth_admin" USING (true);

CREATE POLICY "Allow full access to own chats" ON "public"."chats" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));

CREATE POLICY "Any organization mate can view a user's public profile " ON "public"."user_profiles" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."organization_members"
  WHERE (("organization_members"."member_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("organization_members"."organization_id" IN ( SELECT "organization_members_1"."organization_id"
           FROM "public"."organization_members" "organization_members_1"
          WHERE ("organization_members_1"."member_id" = "user_profiles"."id")))))));

CREATE POLICY "Anyone can view" ON "public"."organization_join_invitations" FOR SELECT USING (true);

CREATE POLICY "Changelog is visible to everyone" ON "public"."internal_changelog" FOR SELECT USING (true);

CREATE POLICY "Enable delete for team admins" ON "public"."projects" FOR DELETE USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("projects"."organization_id") AS "get_organization_admin_ids")));

CREATE POLICY "Enable delete for users based on user_id" ON "public"."organization_members" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("organization_members"."organization_id") AS "get_organization_admin_ids")));

CREATE POLICY "Enable insert for authenticated users only" ON "public"."user_onboarding" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "Enable read access for all organization members" ON "public"."projects" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("projects"."organization_id") AS "get_organization_member_ids")));

CREATE POLICY "Enable read access for all users" ON "public"."organization_credits" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("organization_credits"."organization_id") AS "get_organization_member_ids")));

CREATE POLICY "Enable update for org members" ON "public"."projects" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("projects"."organization_id") AS "get_organization_member_ids"))) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("projects"."organization_id") AS "get_organization_member_ids")));

CREATE POLICY "Everyone can view user profile" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "Everyone organization member can view the subscription on  orga" ON "public"."subscriptions" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("subscriptions"."organization_id") AS "get_organization_member_ids")));

CREATE POLICY "Feedback Comments Create Policy" ON "public"."internal_feedback_comments" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Feedback Comments Owner Delete Policy" ON "public"."internal_feedback_comments" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

CREATE POLICY "Feedback Comments Owner Update Policy" ON "public"."internal_feedback_comments" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

CREATE POLICY "Feedback Comments View Policy" ON "public"."internal_feedback_comments" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "Feedback Threads Create Policy" ON "public"."internal_feedback_threads" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Feedback Threads Owner Delete Policy" ON "public"."internal_feedback_threads" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

CREATE POLICY "Feedback Threads Owner Update Policy" ON "public"."internal_feedback_threads" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

CREATE POLICY "Feedback Threads Visibility Policy" ON "public"."internal_feedback_threads" FOR SELECT USING ((("added_to_roadmap" = true) OR ("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("open_for_public_discussion" = true)));

CREATE POLICY "Inviter can delete the invitation" ON "public"."organization_join_invitations" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "inviter_user_id"));

CREATE POLICY "Only organization admins can insert new members" ON "public"."organization_members" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("organization_members"."organization_id") AS "get_organization_admin_ids")));

CREATE POLICY "Only organization admins can invite other users" ON "public"."organization_join_invitations" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("organization_join_invitations"."organization_id") AS "get_organization_admin_ids")));

CREATE POLICY "Only organization admins can update organization members" ON "public"."organization_members" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("organization_members"."organization_id") AS "get_organization_admin_ids")));

CREATE POLICY "Only organization admins/owners can delete organizations" ON "public"."organizations" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("organizations"."id") AS "get_organization_admin_ids")));

CREATE POLICY "Only organization owners/admins can update private organization" ON "public"."organizations_private_info" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("organizations_private_info"."id") AS "get_organization_admin_ids")));

CREATE POLICY "Only organization owners/admins can view private organizations " ON "public"."organizations_private_info" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_admin_ids"("organizations_private_info"."id") AS "get_organization_admin_ids")));

CREATE POLICY "Only the invited user can edit the invitation" ON "public"."organization_join_invitations" FOR UPDATE TO "authenticated" USING ("public"."check_if_authenticated_user_owns_email"("invitee_user_email"));

CREATE POLICY "Only the own user can update it" ON "public"."user_profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));

CREATE POLICY "Only the user can update their private information" ON "public"."user_private_info" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));

CREATE POLICY "Only the user can view their private information" ON "public"."user_private_info" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));

CREATE POLICY "Person who created the comment can delete it" ON "public"."project_comments" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "Person who created the comment can update it" ON "public"."project_comments" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "Prices of active products are visible" ON "public"."prices" FOR SELECT USING (true);

CREATE POLICY "Temporary : Everyone can view" ON "public"."organization_members" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "User can insert their own keys" ON "public"."user_api_keys" FOR INSERT WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "User can only delete their own deletion token" ON "public"."account_delete_tokens" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "User can only read their own deletion token" ON "public"."account_delete_tokens" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "User can only update their own deletion token" ON "public"."account_delete_tokens" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "User can select their own keys" ON "public"."user_api_keys" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "User can update their own keys" ON "public"."user_api_keys" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "Users can update their onboarding status" ON "public"."user_onboarding" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "Users can view their onboarding status" ON "public"."user_onboarding" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

ALTER TABLE "public"."account_delete_tokens" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "any_user_can_create_notification" ON "public"."user_notifications" FOR INSERT TO "authenticated" WITH CHECK (true);

ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_blog_author_posts" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_blog_author_profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_blog_post_tags" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_blog_post_tags_relationship" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_blog_posts" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_changelog" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_feedback_comments" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."internal_feedback_threads" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "only_user_can_delete_their_notification" ON "public"."user_notifications" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "only_user_can_read_their_own_notification" ON "public"."user_notifications" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));

CREATE POLICY "only_user_can_update_their_notification" ON "public"."user_notifications" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

CREATE POLICY "organization members can view other organization members" ON "public"."organization_members" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") IN ( SELECT "public"."get_organization_member_ids"("organization_members"."organization_id") AS "get_organization_member_ids")));

ALTER TABLE "public"."organization_credits" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."organization_join_invitations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."organization_members" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."organizations_private_info" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."prices" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."project_comments" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_api_keys" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_notifications" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_onboarding" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_private_info" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."user_notifications";

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
GRANT USAGE ON SCHEMA "public" TO "supabase_auth_admin";

REVOKE ALL ON FUNCTION "public"."app_admin_get_all_organizations"("search_query" character varying, "page" integer, "page_size" integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_all_organizations"("search_query" character varying, "page" integer, "page_size" integer) FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_all_organizations"("search_query" character varying, "page" integer, "page_size" integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_all_organizations_count"("search_query" character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."app_admin_get_all_organizations_count"("search_query" character varying) TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_all_users"("search_query" character varying, "page" integer, "page_size" integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_all_users"("search_query" character varying, "page" integer, "page_size" integer) FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_all_users"("search_query" character varying, "page" integer, "page_size" integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_all_users_count"("search_query" character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."app_admin_get_all_users_count"("search_query" character varying) TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_organizations_created_per_month"() FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_organizations_created_per_month"() FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_organizations_created_per_month"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_projects_created_per_month"() FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_projects_created_per_month"() FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_projects_created_per_month"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_recent_30_day_signin_count"() FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_recent_30_day_signin_count"() FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_recent_30_day_signin_count"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_total_organization_count"() FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_total_organization_count"() FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_total_organization_count"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_total_project_count"() FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_total_project_count"() FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_total_project_count"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_total_user_count"() FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_total_user_count"() FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_total_user_count"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_user_id_by_email"("emailarg" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."app_admin_get_user_id_by_email"("emailarg" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."app_admin_get_users_created_per_month"() FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."app_admin_get_users_created_per_month"() FROM "postgres";
GRANT ALL ON FUNCTION "public"."app_admin_get_users_created_per_month"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."check_if_authenticated_user_owns_email"("email" character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_if_authenticated_user_owns_email"("email" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_if_authenticated_user_owns_email"("email" character varying) TO "service_role";

REVOKE ALL ON FUNCTION "public"."check_if_user_is_app_admin"("user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_if_user_is_app_admin"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_if_user_is_app_admin"("user_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."custom_access_token_hook"("event" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."custom_access_token_hook"("event" "jsonb") TO "supabase_auth_admin";

REVOKE ALL ON FUNCTION "public"."decrement_credits"("org_id" "uuid", "amount" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decrement_credits"("org_id" "uuid", "amount" integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_all_app_admins"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_all_app_admins"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_all_app_admins"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_invited_organizations_for_user_v2"("user_id" "uuid", "user_email" character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_invited_organizations_for_user_v2"("user_id" "uuid", "user_email" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_invited_organizations_for_user_v2"("user_id" "uuid", "user_email" character varying) TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_organization_admin_ids"("organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_organization_admin_ids"("organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_organization_admin_ids"("organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organization_admin_ids"("organization_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_organization_id_by_team_id"("p_id" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_organization_id_by_team_id"("p_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organization_id_by_team_id"("p_id" integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_organization_id_for_project_id"("project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_organization_id_for_project_id"("project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organization_id_for_project_id"("project_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_organization_member_ids"("organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_organization_member_ids"("organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_organization_member_ids"("organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organization_member_ids"("organization_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_organizations_for_user"("user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_organizations_for_user"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organizations_for_user"("user_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_team_id_for_project_id"("project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_team_id_for_project_id"("project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_team_id_for_project_id"("project_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_add_organization_member_after_invitation_accepted"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_add_organization_member_after_invitation_accepted"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_add_organization_member_after_invitation_accepted"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_auth_user_created"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_auth_user_created"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_auth_user_created"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_create_welcome_notification"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_create_welcome_notification"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_organization_created"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_organization_created"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_organization_created"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_organization_created_add_credits"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_organization_created_add_credits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_organization_created_add_credits"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."increment_credits"("org_id" "uuid", "amount" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."increment_credits"("org_id" "uuid", "amount" integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."set_default_user_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_default_user_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_default_user_id"() TO "service_role";

GRANT ALL ON TABLE "public"."account_delete_tokens" TO "anon";
GRANT ALL ON TABLE "public"."account_delete_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."account_delete_tokens" TO "service_role";

GRANT ALL ON TABLE "public"."chats" TO "anon";
GRANT ALL ON TABLE "public"."chats" TO "authenticated";
GRANT ALL ON TABLE "public"."chats" TO "service_role";

GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";

GRANT ALL ON TABLE "public"."internal_blog_author_posts" TO "anon";
GRANT ALL ON TABLE "public"."internal_blog_author_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_blog_author_posts" TO "service_role";

GRANT ALL ON TABLE "public"."internal_blog_author_profiles" TO "anon";
GRANT ALL ON TABLE "public"."internal_blog_author_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_blog_author_profiles" TO "service_role";

GRANT ALL ON TABLE "public"."internal_blog_post_tags" TO "anon";
GRANT ALL ON TABLE "public"."internal_blog_post_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_blog_post_tags" TO "service_role";

GRANT ALL ON SEQUENCE "public"."internal_blog_post_tags_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."internal_blog_post_tags_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."internal_blog_post_tags_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."internal_blog_post_tags_relationship" TO "anon";
GRANT ALL ON TABLE "public"."internal_blog_post_tags_relationship" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_blog_post_tags_relationship" TO "service_role";

GRANT ALL ON TABLE "public"."internal_blog_posts" TO "anon";
GRANT ALL ON TABLE "public"."internal_blog_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_blog_posts" TO "service_role";

GRANT ALL ON TABLE "public"."internal_changelog" TO "anon";
GRANT ALL ON TABLE "public"."internal_changelog" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_changelog" TO "service_role";

GRANT ALL ON TABLE "public"."internal_feedback_comments" TO "anon";
GRANT ALL ON TABLE "public"."internal_feedback_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_feedback_comments" TO "service_role";

GRANT ALL ON TABLE "public"."internal_feedback_threads" TO "anon";
GRANT ALL ON TABLE "public"."internal_feedback_threads" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_feedback_threads" TO "service_role";

GRANT ALL ON TABLE "public"."organization_credits" TO "anon";
GRANT ALL ON TABLE "public"."organization_credits" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_credits" TO "service_role";

GRANT ALL ON TABLE "public"."organization_join_invitations" TO "anon";
GRANT ALL ON TABLE "public"."organization_join_invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_join_invitations" TO "service_role";

GRANT ALL ON TABLE "public"."organization_members" TO "anon";
GRANT ALL ON TABLE "public"."organization_members" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_members" TO "service_role";

GRANT ALL ON SEQUENCE "public"."organization_members_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."organization_members_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."organization_members_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";

GRANT ALL ON TABLE "public"."organizations_private_info" TO "anon";
GRANT ALL ON TABLE "public"."organizations_private_info" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations_private_info" TO "service_role";

GRANT ALL ON TABLE "public"."prices" TO "anon";
GRANT ALL ON TABLE "public"."prices" TO "authenticated";
GRANT ALL ON TABLE "public"."prices" TO "service_role";

GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";

GRANT ALL ON TABLE "public"."project_comments" TO "anon";
GRANT ALL ON TABLE "public"."project_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."project_comments" TO "service_role";

GRANT ALL ON SEQUENCE "public"."project_comments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."project_comments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."project_comments_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";

GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";

GRANT ALL ON TABLE "public"."user_api_keys" TO "anon";
GRANT ALL ON TABLE "public"."user_api_keys" TO "authenticated";
GRANT ALL ON TABLE "public"."user_api_keys" TO "service_role";

GRANT ALL ON TABLE "public"."user_notifications" TO "anon";
GRANT ALL ON TABLE "public"."user_notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."user_notifications" TO "service_role";

GRANT ALL ON TABLE "public"."user_onboarding" TO "anon";
GRANT ALL ON TABLE "public"."user_onboarding" TO "authenticated";
GRANT ALL ON TABLE "public"."user_onboarding" TO "service_role";

GRANT ALL ON TABLE "public"."user_private_info" TO "anon";
GRANT ALL ON TABLE "public"."user_private_info" TO "authenticated";
GRANT ALL ON TABLE "public"."user_private_info" TO "service_role";

GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";

GRANT ALL ON TABLE "public"."user_roles" TO "service_role";
GRANT ALL ON TABLE "public"."user_roles" TO "supabase_auth_admin";

GRANT ALL ON SEQUENCE "public"."user_roles_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_roles_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_roles_id_seq" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";

RESET ALL;

--
-- Dumped schema changes for auth and storage
--

CREATE OR REPLACE TRIGGER "on_auth_user_created_create_profile" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_auth_user_created"();

CREATE OR REPLACE TRIGGER "on_auth_user_created_create_welcome_notification" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_create_welcome_notification"();

CREATE POLICY "Allow users to read their changelog assets" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'changelog-assets'::"text"));

CREATE POLICY "Allow users to read their openai images" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'openai-images'::"text"));

CREATE POLICY "Give users access to own folder 10fq7k5_0" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'user-assets'::"text") AND ((( SELECT ( SELECT "auth"."uid"() AS "uid") AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));

CREATE POLICY "Give users access to own folder 10fq7k5_1" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'user-assets'::"text") AND ((( SELECT "auth"."uid"() AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));

CREATE POLICY "Give users access to own folder 10fq7k5_2" ON "storage"."objects" FOR UPDATE TO "authenticated" USING ((("bucket_id" = 'user-assets'::"text") AND ((( SELECT "auth"."uid"() AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));

CREATE POLICY "Give users access to own folder 10fq7k5_3" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'user-assets'::"text") AND ((( SELECT "auth"."uid"() AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));

CREATE POLICY "Give users access to own folder 1plzjhd_0" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'public-user-assets'::"text"));

CREATE POLICY "Give users access to own folder 1plzjhd_1" ON "storage"."objects" FOR INSERT WITH CHECK ((("bucket_id" = 'public-user-assets'::"text") AND ((( SELECT "auth"."uid"() AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));

CREATE POLICY "Give users access to own folder 1plzjhd_2" ON "storage"."objects" FOR UPDATE USING ((("bucket_id" = 'public-user-assets'::"text") AND ((( SELECT "auth"."uid"() AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));

CREATE POLICY "Give users access to own folder 1plzjhd_3" ON "storage"."objects" FOR DELETE USING ((("bucket_id" = 'public-user-assets'::"text") AND ((( SELECT "auth"."uid"() AS "uid"))::"text" = ("storage"."foldername"("name"))[1])));

CREATE POLICY "Public Access for admin-blog " ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'admin-blog'::"text"));

CREATE POLICY "Public Access for public-assets 1plzjha_3" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'public-assets'::"text"));

CREATE POLICY "anything 1plzjhd_0" ON "storage"."objects" FOR UPDATE USING (true);

CREATE POLICY "anything 1plzjhd_1" ON "storage"."objects" FOR SELECT USING (true);

CREATE POLICY "anything 1plzjhd_2" ON "storage"."objects" FOR DELETE USING (true);

GRANT SELECT ON TABLE "auth"."audit_log_entries" TO "service_role";
GRANT SELECT ON TABLE "auth"."flow_state" TO "service_role";
GRANT SELECT ON TABLE "auth"."identities" TO "service_role";
GRANT SELECT ON TABLE "auth"."instances" TO "service_role";
GRANT SELECT ON TABLE "auth"."mfa_amr_claims" TO "service_role";
GRANT SELECT ON TABLE "auth"."mfa_challenges" TO "service_role";
GRANT SELECT ON TABLE "auth"."mfa_factors" TO "service_role";
GRANT SELECT ON TABLE "auth"."one_time_tokens" TO "service_role";
GRANT SELECT ON TABLE "auth"."refresh_tokens" TO "service_role";
GRANT SELECT ON TABLE "auth"."saml_providers" TO "service_role";
GRANT SELECT ON TABLE "auth"."saml_relay_states" TO "service_role";
GRANT SELECT ON TABLE "auth"."schema_migrations" TO "service_role";
GRANT SELECT ON TABLE "auth"."sessions" TO "service_role";
GRANT SELECT ON TABLE "auth"."sso_domains" TO "service_role";
GRANT SELECT ON TABLE "auth"."sso_providers" TO "service_role";
GRANT SELECT ON TABLE "auth"."users" TO "service_role";
