/*
 * DEVICES TRUST COLUMNS
 *
 * Add trust-related columns to devices table for device-rooted trust model.
 * Part of NEX-614: Trust Architecture Schema Migrations
 */

-- Add device role column (defaults to trusted_executor for existing devices)
ALTER TABLE "public"."devices"
  ADD COLUMN IF NOT EXISTS "device_role" "public"."device_role" DEFAULT 'trusted_executor'::"public"."device_role" NOT NULL;

-- Add public key for X25519 key exchange (base64 encoded)
ALTER TABLE "public"."devices"
  ADD COLUMN IF NOT EXISTS "public_key" TEXT;

-- Flag for primary trust root device (only one per user)
ALTER TABLE "public"."devices"
  ADD COLUMN IF NOT EXISTS "is_primary_trust_root" BOOLEAN DEFAULT FALSE NOT NULL;

-- When the device was verified by trust root
ALTER TABLE "public"."devices"
  ADD COLUMN IF NOT EXISTS "verified_at" TIMESTAMP WITH TIME ZONE;

-- Create partial unique index to ensure only one primary trust root per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_primary_trust_root_unique
  ON "public"."devices"("user_id")
  WHERE "is_primary_trust_root" = TRUE;

-- Index for device role queries
CREATE INDEX IF NOT EXISTS idx_devices_device_role
  ON "public"."devices"("device_role");

-- Index for verified devices
CREATE INDEX IF NOT EXISTS idx_devices_verified
  ON "public"."devices"("user_id", "verified_at")
  WHERE "verified_at" IS NOT NULL;

-- Add comments for new columns
COMMENT ON COLUMN "public"."devices"."device_role" IS 'Role in trust hierarchy: trust_root (phone), trusted_executor (mac), temporary_viewer (web)';
COMMENT ON COLUMN "public"."devices"."public_key" IS 'X25519 long-term public key for device (base64 encoded)';
COMMENT ON COLUMN "public"."devices"."is_primary_trust_root" IS 'Whether this is the primary trust root device for the user (only one allowed)';
COMMENT ON COLUMN "public"."devices"."verified_at" IS 'When this device was verified/approved by the trust root';
