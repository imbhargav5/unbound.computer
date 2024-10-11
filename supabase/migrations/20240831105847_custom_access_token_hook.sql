CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb) RETURNS jsonb language plpgsql AS $$
DECLARE -- Insert variables here
  claims jsonb;
nextbase_app_role public.app_role;
BEGIN -- Insert logic here
-- Check if the user is marked as admin in the profiles table
SELECT role INTO nextbase_app_role
FROM public.user_roles
WHERE user_id = (event->>'user_id')::uuid;

claims := event->'claims';
-- Ensure app_metadata exists
IF claims->'app_metadata' IS NULL THEN claims := jsonb_set(claims, '{app_metadata}', '{}');
END IF;
-- Update the claims with the role
claims := jsonb_set(
  claims,
  '{app_metadata,nextbase_app_role}',
  to_jsonb(
    COALESCE(nextbase_app_role::text, 'default_role')
  )
);

  -- Update the event with the modified claims
event := jsonb_set(event, '{claims}', claims);

  -- Log the updated event
RAISE NOTICE 'Updated event: %',
event;

  RETURN event;
END;
$$;
-- Permissions for the hook
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook
FROM authenticated,
  anon,
  public;