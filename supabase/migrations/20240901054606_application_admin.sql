CREATE OR REPLACE FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") RETURNS "void" LANGUAGE "plpgsql"
SET search_path = public,
  pg_temp AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only supabase_admin, dashboard_user, postgres can execute this function';
END IF;

INSERT INTO public.user_roles (user_id, role)
VALUES (user_id_arg, 'admin') ON CONFLICT (user_id, role) DO NOTHING;


END;
$$;

ALTER FUNCTION "public"."make_user_app_admin"("user_id_arg" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION public.make_user_app_admin(uuid)
FROM public,
  anon,
  authenticated,
  service_role;

CREATE OR REPLACE FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") RETURNS "void" LANGUAGE "plpgsql"
SET search_path = public,
  pg_temp AS $$ BEGIN IF CURRENT_ROLE NOT IN (
    'supabase_admin',
    'dashboard_user',
    'postgres'
  ) THEN RAISE EXCEPTION 'Only  supabase_admin, dashboard_user, postgres can execute this function';
END IF;

DELETE FROM public.user_roles
WHERE user_id = user_id_arg
  AND role = 'admin';


END;
$$;

ALTER FUNCTION "public"."remove_app_admin_privilege_for_user"("user_id_arg" "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION public.remove_app_admin_privilege_for_user(uuid)
FROM public,
  anon,
  authenticated,
  service_role;