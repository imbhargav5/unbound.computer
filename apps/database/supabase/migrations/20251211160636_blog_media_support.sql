-- Add media_type column to marketing_blog_posts for video/GIF support
ALTER TABLE marketing_blog_posts
ADD COLUMN media_type VARCHAR CHECK (media_type IS NULL OR media_type IN ('image', 'video', 'gif'));

COMMENT ON COLUMN marketing_blog_posts.media_type IS 'Type of cover media: image, video, or gif';
