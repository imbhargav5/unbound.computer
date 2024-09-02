CREATE OR REPLACE FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") RETURNS "void" LANGUAGE "plpgsql" AS $$ BEGIN IF CURRENT_ROLE NOT IN (
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

CREATE OR REPLACE FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") RETURNS "void" LANGUAGE "plpgsql" AS $$ BEGIN IF CURRENT_ROLE NOT IN (
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

CREATE OR REPLACE FUNCTION "public"."set_default_user_id"() RETURNS "trigger" LANGUAGE "plpgsql" AS $$ BEGIN IF NEW.user_id IS NULL THEN NEW.user_id := auth.uid();
END IF;
RETURN NEW;
END;
$$;