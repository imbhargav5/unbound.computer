/*
 * DEVICE PAIRWISE SECRETS
 *
 * Stores encrypted pairwise secrets between device pairs.
 * Each device can decrypt only its copy using its own private key.
 * Part of NEX-614: Trust Architecture Schema Migrations
 */

CREATE TABLE IF NOT EXISTS "public"."device_pairwise_secrets" (
  "id" UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  "user_id" UUID NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,

  -- Device pair (ordered by ID to ensure consistent storage)
  "device_a_id" UUID NOT NULL REFERENCES "public"."devices"("id") ON DELETE CASCADE,
  "device_b_id" UUID NOT NULL REFERENCES "public"."devices"("id") ON DELETE CASCADE,

  -- Encrypted copies of the pairwise secret (each encrypted with recipient's public key)
  -- Format: base64(nonce || ciphertext || tag)
  "encrypted_secret_for_a" TEXT NOT NULL,
  "encrypted_secret_for_b" TEXT NOT NULL,

  -- Key agreement algorithm used
  "key_algorithm" TEXT DEFAULT 'X25519-XChaCha20-Poly1305' NOT NULL,

  -- Timestamps
  "created_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

  -- Ensure device_a_id < device_b_id for consistent ordering
  CONSTRAINT "device_pairwise_secrets_ordering" CHECK ("device_a_id" < "device_b_id"),

  -- Unique secret per device pair
  CONSTRAINT "device_pairwise_secrets_unique_pair" UNIQUE ("device_a_id", "device_b_id")
);

COMMENT ON TABLE "public"."device_pairwise_secrets" IS 'Encrypted pairwise secrets between device pairs. Each device stores its own encrypted copy.';

ALTER TABLE "public"."device_pairwise_secrets" OWNER TO postgres;

-- Indexes for device lookups
CREATE INDEX idx_device_pairwise_secrets_user_id ON "public"."device_pairwise_secrets"("user_id");
CREATE INDEX idx_device_pairwise_secrets_device_a ON "public"."device_pairwise_secrets"("device_a_id");
CREATE INDEX idx_device_pairwise_secrets_device_b ON "public"."device_pairwise_secrets"("device_b_id");

-- Enable RLS
ALTER TABLE "public"."device_pairwise_secrets" ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own pairwise secrets" ON "public"."device_pairwise_secrets"
  FOR SELECT TO authenticated
  USING ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can create pairwise secrets for their devices" ON "public"."device_pairwise_secrets"
  FOR INSERT TO authenticated
  WITH CHECK ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can update their own pairwise secrets" ON "public"."device_pairwise_secrets"
  FOR UPDATE TO authenticated
  USING ("user_id" = (SELECT auth.uid()))
  WITH CHECK ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can delete their own pairwise secrets" ON "public"."device_pairwise_secrets"
  FOR DELETE TO authenticated
  USING ("user_id" = (SELECT auth.uid()));

-- Function to get or create pairwise secret record for two devices
CREATE OR REPLACE FUNCTION "public"."get_device_pair_id"(
  "p_device_id_1" UUID,
  "p_device_id_2" UUID
)
RETURNS TABLE("device_a" UUID, "device_b" UUID)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Return devices in consistent order (smaller UUID first)
  IF p_device_id_1 < p_device_id_2 THEN
    RETURN QUERY SELECT p_device_id_1, p_device_id_2;
  ELSE
    RETURN QUERY SELECT p_device_id_2, p_device_id_1;
  END IF;
END;
$$;

COMMENT ON FUNCTION "public"."get_device_pair_id"(UUID, UUID) IS 'Returns device IDs in consistent order for pairwise secret lookups.';
