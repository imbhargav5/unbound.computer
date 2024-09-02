CREATE POLICY "Allow users to read their changelog assets" ON "storage"."objects" FOR
SELECT USING (("bucket_id" = 'changelog-assets'::"text"));

CREATE POLICY "Allow users to read their openai images" ON "storage"."objects" FOR
SELECT USING (("bucket_id" = 'openai-images'::"text"));

CREATE POLICY "Give users access to own folder 10fq7k5_0" ON "storage"."objects" FOR
SELECT TO "authenticated" USING (
    (
      ("bucket_id" = 'user-assets'::"text")
      AND (
        (
          (
            SELECT (
                SELECT "auth"."uid"() AS "uid"
              ) AS "uid"
          )
        )::"text" = ("storage"."foldername"("name")) [1]
      )
    )
  );

CREATE POLICY "Give users access to own folder 10fq7k5_1" ON "storage"."objects" FOR
INSERT TO "authenticated" WITH CHECK (
    (
      ("bucket_id" = 'user-assets'::"text")
      AND (
        (
          (
            SELECT "auth"."uid"() AS "uid"
          )
        )::"text" = ("storage"."foldername"("name")) [1]
      )
    )
  );

CREATE POLICY "Give users access to own folder 10fq7k5_2" ON "storage"."objects" FOR
UPDATE TO "authenticated" USING (
    (
      ("bucket_id" = 'user-assets'::"text")
      AND (
        (
          (
            SELECT "auth"."uid"() AS "uid"
          )
        )::"text" = ("storage"."foldername"("name")) [1]
      )
    )
  );

CREATE POLICY "Give users access to own folder 10fq7k5_3" ON "storage"."objects" FOR DELETE TO "authenticated" USING (
  (
    ("bucket_id" = 'user-assets'::"text")
    AND (
      (
        (
          SELECT "auth"."uid"() AS "uid"
        )
      )::"text" = ("storage"."foldername"("name")) [1]
    )
  )
);

CREATE POLICY "Give users access to own folder 1plzjhd_0" ON "storage"."objects" FOR
SELECT USING (("bucket_id" = 'public-user-assets'::"text"));

CREATE POLICY "Give users access to own folder 1plzjhd_1" ON "storage"."objects" FOR
INSERT WITH CHECK (
    (
      ("bucket_id" = 'public-user-assets'::"text")
      AND (
        (
          (
            SELECT "auth"."uid"() AS "uid"
          )
        )::"text" = ("storage"."foldername"("name")) [1]
      )
    )
  );

CREATE POLICY "Give users access to own folder 1plzjhd_2" ON "storage"."objects" FOR
UPDATE USING (
    (
      ("bucket_id" = 'public-user-assets'::"text")
      AND (
        (
          (
            SELECT "auth"."uid"() AS "uid"
          )
        )::"text" = ("storage"."foldername"("name")) [1]
      )
    )
  );

CREATE POLICY "Give users access to own folder 1plzjhd_3" ON "storage"."objects" FOR DELETE USING (
  (
    ("bucket_id" = 'public-user-assets'::"text")
    AND (
      (
        (
          SELECT "auth"."uid"() AS "uid"
        )
      )::"text" = ("storage"."foldername"("name")) [1]
    )
  )
);

CREATE POLICY "Public Access for admin-blog " ON "storage"."objects" FOR
SELECT USING (("bucket_id" = 'admin-blog'::"text"));

CREATE POLICY "Public Access for public-assets 1plzjha_3" ON "storage"."objects" FOR
SELECT USING (("bucket_id" = 'public-assets'::"text"));

CREATE POLICY "anything 1plzjhd_0" ON "storage"."objects" FOR
UPDATE USING (TRUE);

CREATE POLICY "anything 1plzjhd_1" ON "storage"."objects" FOR
SELECT USING (TRUE);

CREATE POLICY "anything 1plzjhd_2" ON "storage"."objects" FOR DELETE USING (TRUE);