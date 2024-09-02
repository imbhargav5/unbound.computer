/*
 _____ _    _  _____ ______ _____   _____  _____   ____  ______ _____ _      ______  _____
 |_   _| |  | |/ ____|  ____|  __ \ |  __ \|  __ \ / __ \|  ____|_   _| |    |  ____|/ ____|
 | | | |  | | (___ | |__  | |__) || |__) | |__) | |  | | |__    | | | |    | |__  | (___
 | | | |  | |\___ \|  __| |  _  / |  ___/|  _  /| |  | |  __|   | | | |    |  __|  \___ \
 _| |_| |__| |____) | |____| | \ \ | |    | | \ \| |__| | |     _| |_| |____| |____ ____) |
 |_____|\____/|_____/|______|_|  \_\|_|    |_|  \_\\____/|_|    |_____|______|______|_____/
 
 This file contains the database schema for user-related tables:
 - user_private_info: Stores private user information
 - user_profiles: Stores public user profile information
 - user_roles: Manages user roles within the application
 
 These tables form the foundation of the user management system in our application.
 */
CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
  "id" "uuid" PRIMARY KEY NOT NULL REFERENCES "auth"."users"("id") ON DELETE CASCADE,
  "full_name" character varying,
  "avatar_url" character varying,
  "created_at" timestamp WITH time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."user_profiles" OWNER TO "postgres";
ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS "public"."user_private_info" (
  "id" "uuid" PRIMARY KEY NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,
  "created_at" timestamp WITH time zone DEFAULT "now"(),
  "default_organization" "uuid",
  "email_readonly" character varying NOT NULL
);

ALTER TABLE "public"."user_private_info" OWNER TO "postgres";
ALTER TABLE "public"."user_private_info" ENABLE ROW LEVEL SECURITY;



CREATE TABLE IF NOT EXISTS "public"."user_roles" (
  "id" UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  "user_id" UUID NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,
  "role" "public"."app_role" NOT NULL
);

ALTER TABLE "public"."user_roles"
ADD CONSTRAINT "user_roles_user_id_role_key" UNIQUE ("user_id", "role");

ALTER TABLE "public"."user_roles" OWNER TO "postgres";
COMMENT ON TABLE "public"."user_roles" IS 'Application roles for each user.';
ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS "public"."user_api_keys" (
  "key_id" "text" NOT NULL,
  "masked_key" "text" NOT NULL,
  "created_at" timestamp WITH time zone DEFAULT "now"() NOT NULL,
  "user_id" "uuid" NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,
  "expires_at" timestamp WITH time zone,
  "is_revoked" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."user_api_keys" OWNER TO "postgres";
ALTER TABLE "public"."user_api_keys" ENABLE ROW LEVEL SECURITY;
CREATE TABLE IF NOT EXISTS "public"."user_notifications" (
  "id" "uuid" PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  "user_id" "uuid" NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,
  "is_read" boolean DEFAULT false NOT NULL,
  "is_seen" boolean DEFAULT false NOT NULL,
  "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
  "created_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE "public"."user_notifications" OWNER TO "postgres";
ALTER TABLE "public"."user_notifications" ENABLE ROW LEVEL SECURITY;

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";

ALTER PUBLICATION "supabase_realtime"
ADD TABLE ONLY "public"."user_notifications";

CREATE TABLE IF NOT EXISTS "public"."account_delete_tokens" (
  "token" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  "user_id" "uuid" NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."account_delete_tokens" OWNER TO "postgres";
ALTER TABLE "public"."account_delete_tokens" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated users can request deletion" ON "public"."account_delete_tokens" FOR
INSERT TO "authenticated" WITH CHECK (TRUE);


-- Row Level Security (RLS) policies
---------------------------------------------------------------------------
-- These policies control access to the tables based on the user's role and
-- permissions. They ensure data privacy and security at the database level.
---------------------------------------------------------------------------
-- User Profiles RLS
CREATE POLICY "Everyone can view user profile" ON "public"."user_profiles" FOR
SELECT TO "authenticated" USING (TRUE);

CREATE POLICY "Only the own user can update it" ON "public"."user_profiles" FOR
UPDATE TO "authenticated" USING (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "id"
    )
  );
-- User Roles RLS
CREATE POLICY "Users can view their own roles" ON "public"."user_roles" FOR
SELECT TO authenticated USING (
    (
      SELECT "auth"."uid"() AS "uid"
    ) = user_id
  );

CREATE POLICY "Allow auth admin to read user roles" ON "public"."user_roles" FOR
SELECT TO "supabase_auth_admin" USING (TRUE);

-- User API Keys RLS
CREATE POLICY "User can select their own keys" ON "public"."user_api_keys" FOR
SELECT USING (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  );


CREATE POLICY "User can update their own keys" ON "public"."user_api_keys" FOR
UPDATE USING (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  ) WITH CHECK (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  );
-- User Notifications RLS
CREATE POLICY "any_user_can_create_notification" ON "public"."user_notifications" FOR
INSERT TO "authenticated" WITH CHECK (TRUE);



CREATE POLICY "only_user_can_delete_their_notification" ON "public"."user_notifications" FOR DELETE TO "authenticated" USING (
  (
    (
      SELECT "auth"."uid"() AS "uid"
    ) = "user_id"
  )
);

CREATE POLICY "only_user_can_read_their_own_notification" ON "public"."user_notifications" FOR
SELECT TO "authenticated" USING (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  );

CREATE POLICY "only_user_can_update_their_notification" ON "public"."user_notifications" FOR
UPDATE TO "authenticated" USING (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  );

CREATE POLICY "Users can update their own notifications" ON "public"."user_notifications" FOR
UPDATE TO authenticated USING (
    (
      SELECT "auth"."uid"() AS "uid"
    ) = user_id
  );

-- Account Delete Tokens RLS
CREATE POLICY "User can insert their own keys" ON "public"."user_api_keys" FOR
INSERT WITH CHECK (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  );


CREATE POLICY "User can only delete their own deletion token" ON "public"."account_delete_tokens" FOR DELETE TO "authenticated" USING (
  (
    (
      SELECT "auth"."uid"() AS "uid"
    ) = "user_id"
  )
);

CREATE POLICY "User can only read their own deletion token" ON "public"."account_delete_tokens" FOR
SELECT TO "authenticated" USING (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  );

CREATE POLICY "User can only update their own deletion token" ON "public"."account_delete_tokens" FOR
UPDATE TO "authenticated" USING (
    (
      (
        SELECT "auth"."uid"() AS "uid"
      ) = "user_id"
    )
  );

/*
 * Sync email for convenience
 */
-- Function to update email_readonly in user_private_info
CREATE OR REPLACE FUNCTION public.update_user_private_info_email() RETURNS TRIGGER AS $$ BEGIN
UPDATE public.user_private_info
SET email_readonly = NEW.email
WHERE id = NEW.id;
RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update email_readonly when auth.users email is updated
CREATE TRIGGER on_auth_user_email_updated
AFTER
UPDATE OF email ON auth.users FOR EACH ROW EXECUTE FUNCTION public.update_user_private_info_email();

-- Revoke execute permission from PUBLIC
REVOKE EXECUTE ON FUNCTION public.update_user_private_info_email()
FROM PUBLIC;

-- Grant execute permission only to postgres and service_role
GRANT EXECUTE ON FUNCTION public.update_user_private_info_email() TO postgres,
  service_role;