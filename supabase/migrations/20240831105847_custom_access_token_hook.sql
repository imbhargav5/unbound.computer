CREATE OR REPLACE FUNCTION "public"."custom_access_token_hook"("event" "jsonb") RETURNS "jsonb" LANGUAGE "plpgsql" SECURITY DEFINER IMMUTABLE AS $$
DECLARE claims jsonb;
user_role public.app_role;
BEGIN -- Check if the user is marked as admin in the profiles table
SELECT role INTO user_role
FROM public.user_roles
WHERE user_id = (event->>'user_id')::uuid;

    claims := event->'claims';

IF user_role IS NOT NULL THEN -- Set the claim
claims := jsonb_set(
  claims,
  '{app_metadata,user_role}',
  to_jsonb(user_role)
);

END IF;
-- Update the 'claims' object in the original event
event := jsonb_set(event, '{claims}', claims);

-- Return the modified or original event
RETURN event;
RAISE WARNING 'event: %',
event;
END;
$$;

REVOKE ALL ON FUNCTION public.custom_access_token_hook(jsonb)
FROM anon,
  authenticated,
  public;

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
GRANT USAGE ON schema public TO supabase_auth_admin;
GRANT USAGE ON schema auth TO supabase_auth_admin;

ALTER FUNCTION "public"."custom_access_token_hook"("event" "jsonb") OWNER TO "postgres";


GRANT ALL ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
GRANT ALL ON TABLE public.user_roles TO supabase_auth_admin;