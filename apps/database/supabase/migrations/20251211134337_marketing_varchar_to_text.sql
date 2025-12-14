-- UP Migration: Convert VARCHAR(255) to TEXT

-- marketing_author_profiles
ALTER TABLE public.marketing_author_profiles
  ALTER COLUMN display_name TYPE text,
  ALTER COLUMN avatar_url TYPE text,
  ALTER COLUMN website_url TYPE text,
  ALTER COLUMN twitter_handle TYPE text,
  ALTER COLUMN facebook_handle TYPE text,
  ALTER COLUMN linkedin_handle TYPE text,
  ALTER COLUMN instagram_handle TYPE text;

-- marketing_blog_posts
ALTER TABLE public.marketing_blog_posts
  ALTER COLUMN slug TYPE text,
  ALTER COLUMN title TYPE text,
  ALTER COLUMN cover_image TYPE text;

-- DOWN Migration (rollback):
-- ALTER TABLE public.marketing_author_profiles
--   ALTER COLUMN display_name TYPE character varying(255),
--   ALTER COLUMN avatar_url TYPE character varying(255),
--   ALTER COLUMN website_url TYPE character varying(255),
--   ALTER COLUMN twitter_handle TYPE character varying(255),
--   ALTER COLUMN facebook_handle TYPE character varying(255),
--   ALTER COLUMN linkedin_handle TYPE character varying(255),
--   ALTER COLUMN instagram_handle TYPE character varying(255);
--
-- ALTER TABLE public.marketing_blog_posts
--   ALTER COLUMN slug TYPE character varying(255),
--   ALTER COLUMN title TYPE character varying(255),
--   ALTER COLUMN cover_image TYPE character varying(255);
