/*
 * DEVICE TRUST GRAPH
 *
 * Tracks trust relationships between devices for device-rooted trust model.
 * Trust flows from trust_root (phone) to other devices.
 * Part of NEX-614: Trust Architecture Schema Migrations
 */

CREATE TABLE IF NOT EXISTS "public"."device_trust_graph" (
  "id" UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  "user_id" UUID NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,

  -- The device granting trust
  "grantor_device_id" UUID NOT NULL REFERENCES "public"."devices"("id") ON DELETE CASCADE,

  -- The device receiving trust
  "grantee_device_id" UUID NOT NULL REFERENCES "public"."devices"("id") ON DELETE CASCADE,

  -- Trust relationship status
  "status" "public"."trust_relationship_status" DEFAULT 'pending'::"public"."trust_relationship_status" NOT NULL,

  -- Trust level (1 = direct from trust root, 2 = one hop, 3 = max)
  "trust_level" INTEGER NOT NULL CHECK ("trust_level" >= 1 AND "trust_level" <= 3),

  -- Timestamps
  "created_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  "approved_at" TIMESTAMP WITH TIME ZONE,
  "expires_at" TIMESTAMP WITH TIME ZONE,
  "revoked_at" TIMESTAMP WITH TIME ZONE,
  "revoked_reason" TEXT,

  -- Ensure grantor and grantee are different devices
  CONSTRAINT "device_trust_graph_different_devices" CHECK ("grantor_device_id" != "grantee_device_id"),

  -- Unique trust relationship per device pair
  CONSTRAINT "device_trust_graph_unique_relationship" UNIQUE ("grantor_device_id", "grantee_device_id")
);

COMMENT ON TABLE "public"."device_trust_graph" IS 'Trust relationships between devices. Trust flows from trust_root (phone) to executors and viewers.';

ALTER TABLE "public"."device_trust_graph" OWNER TO postgres;

-- Indexes for common queries
CREATE INDEX idx_device_trust_graph_user_id ON "public"."device_trust_graph"("user_id");
CREATE INDEX idx_device_trust_graph_grantor ON "public"."device_trust_graph"("grantor_device_id");
CREATE INDEX idx_device_trust_graph_grantee ON "public"."device_trust_graph"("grantee_device_id");
CREATE INDEX idx_device_trust_graph_status ON "public"."device_trust_graph"("status");
CREATE INDEX idx_device_trust_graph_active ON "public"."device_trust_graph"("grantee_device_id", "status")
  WHERE "status" = 'active';

-- Enable RLS
ALTER TABLE "public"."device_trust_graph" ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own trust relationships" ON "public"."device_trust_graph"
  FOR SELECT TO authenticated
  USING ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can create trust relationships for their devices" ON "public"."device_trust_graph"
  FOR INSERT TO authenticated
  WITH CHECK ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can update their own trust relationships" ON "public"."device_trust_graph"
  FOR UPDATE TO authenticated
  USING ("user_id" = (SELECT auth.uid()))
  WITH CHECK ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can delete their own trust relationships" ON "public"."device_trust_graph"
  FOR DELETE TO authenticated
  USING ("user_id" = (SELECT auth.uid()));
