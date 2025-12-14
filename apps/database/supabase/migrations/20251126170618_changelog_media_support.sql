-- Add new columns for enhanced changelog functionality
-- Supports: version numbers, tags, media (image/video/gif), technical details

-- Add version column for semantic versioning (e.g., "v2.1.0")
ALTER TABLE marketing_changelog
ADD COLUMN IF NOT EXISTS version VARCHAR(20);

-- Add tags as an array of strings for categorization
ALTER TABLE marketing_changelog
ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

-- Add media type to distinguish between image, video, and gif
ALTER TABLE marketing_changelog
ADD COLUMN IF NOT EXISTS media_type VARCHAR(20) CHECK (media_type IS NULL OR media_type IN ('image', 'video', 'gif'));

-- Add media URL for the featured media
ALTER TABLE marketing_changelog
ADD COLUMN IF NOT EXISTS media_url TEXT;

-- Add alt text for accessibility
ALTER TABLE marketing_changelog
ADD COLUMN IF NOT EXISTS media_alt TEXT;

-- Add technical details for expandable technical section (markdown)
ALTER TABLE marketing_changelog
ADD COLUMN IF NOT EXISTS technical_details TEXT;

-- Migrate existing cover_image data to new media fields
UPDATE marketing_changelog
SET media_type = 'image', media_url = cover_image
WHERE cover_image IS NOT NULL AND media_url IS NULL;

-- Add index on tags for efficient filtering
CREATE INDEX IF NOT EXISTS idx_marketing_changelog_tags ON marketing_changelog USING GIN (tags);

-- Add index on version for sorting/filtering
CREATE INDEX IF NOT EXISTS idx_marketing_changelog_version ON marketing_changelog (version);
