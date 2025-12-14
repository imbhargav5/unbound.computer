-- Add media_poster column to marketing_changelog
ALTER TABLE marketing_changelog
ADD COLUMN IF NOT EXISTS media_poster TEXT;

COMMENT ON COLUMN marketing_changelog.media_poster IS 'Poster/thumbnail image URL for videos';

-- Add media_poster column to marketing_blog_posts
ALTER TABLE marketing_blog_posts
ADD COLUMN IF NOT EXISTS media_poster TEXT;

COMMENT ON COLUMN marketing_blog_posts.media_poster IS 'Poster/thumbnail image URL for videos';
