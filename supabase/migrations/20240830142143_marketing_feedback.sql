CREATE TABLE IF NOT EXISTS "public"."marketing_changelog" (
  "id" "uuid" PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  "title" character varying(255) NOT NULL,
  "changes" "text" NOT NULL,
  "created_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP,
  "updated_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP,
  "cover_image" "text"
);

ALTER TABLE "public"."marketing_changelog" OWNER TO "postgres";
ALTER TABLE "public"."marketing_changelog" ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS "public"."marketing_changelog_author_relationship" (
  "author_id" "uuid" NOT NULL REFERENCES "public"."marketing_author_profiles"("id") ON DELETE CASCADE,
  "changelog_id" "uuid" NOT NULL REFERENCES "public"."marketing_changelog"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."marketing_changelog_author_relationship" OWNER TO "postgres";
ALTER TABLE "public"."marketing_changelog_author_relationship" ENABLE ROW LEVEL SECURITY;




CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_threads" (
  "id" "uuid" PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  "title" character varying(255) NOT NULL,
  "content" "text" NOT NULL,
  "user_id" "uuid" NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,
  "created_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "priority" "public"."marketing_feedback_thread_priority" DEFAULT 'low'::"public"."marketing_feedback_thread_priority" NOT NULL,
  "type" "public"."marketing_feedback_thread_type" DEFAULT 'general'::"public"."marketing_feedback_thread_type" NOT NULL,
  "status" "public"."marketing_feedback_thread_status" DEFAULT 'open'::"public"."marketing_feedback_thread_status" NOT NULL,
  "added_to_roadmap" boolean DEFAULT false NOT NULL,
  "open_for_public_discussion" boolean DEFAULT false NOT NULL,
  "is_publicly_visible" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."marketing_feedback_threads" OWNER TO "postgres";
ALTER TABLE "public"."marketing_feedback_threads" ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS "public"."marketing_feedback_comments" (
  "id" "uuid" PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  "user_id" "uuid" NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,
  "thread_id" "uuid" NOT NULL REFERENCES "public"."marketing_feedback_threads"("id") ON DELETE CASCADE,
  "content" "text" NOT NULL,
  "created_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp WITH time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."marketing_feedback_comments" OWNER TO "postgres";
ALTER TABLE "public"."marketing_feedback_comments" ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "Authenticated users can create feedback comments" ON "public"."marketing_feedback_comments" FOR
INSERT TO "authenticated" WITH CHECK (TRUE);

-- Own user can update comments
CREATE POLICY "Authenticated users can update their own feedback comments" ON "public"."marketing_feedback_comments" FOR
UPDATE USING ("user_id" = "auth"."uid"()) WITH CHECK ("user_id" = "auth"."uid"());

-- Own user can delete comments
CREATE POLICY "Authenticated users can delete their own feedback comments" ON "public"."marketing_feedback_comments" FOR DELETE USING ("user_id" = "auth"."uid"());


-- threads
CREATE POLICY "Authenticated users can create feedback threads" ON "public"."marketing_feedback_threads" FOR
INSERT TO "authenticated" WITH CHECK (TRUE);

CREATE POLICY "Authenticated users can delete their own feedback threads" ON "public"."marketing_feedback_threads" FOR DELETE TO "authenticated" USING (
  (
    "user_id" = (
      SELECT "auth"."uid"() AS "uid"
    )
  )
);

CREATE POLICY "Authenticated users can update their own feedback threads" ON "public"."marketing_feedback_threads" FOR
UPDATE TO "authenticated" USING (
    (
      "user_id" = (
        SELECT "auth"."uid"() AS "uid"
      )
    )
  );

CREATE POLICY "Authenticated users can view feedback threads if they are added to the roadmap or if the thread is open for public discussion" ON "public"."marketing_feedback_threads" FOR
SELECT USING (
    (
      ("added_to_roadmap" = TRUE)
      OR (
        "user_id" = (
          SELECT "auth"."uid"() AS "uid"
        )
      )
      OR ("open_for_public_discussion" = TRUE)
    )
  );

  -- changelog
CREATE POLICY "Changelog is visible to everyone" ON "public"."marketing_changelog" FOR
SELECT USING (TRUE);

CREATE POLICY "Changelog author relationship is visible to everyone" ON "public"."marketing_changelog_author_relationship" FOR
SELECT USING (TRUE);