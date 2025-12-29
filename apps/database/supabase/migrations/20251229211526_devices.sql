/*
 * DEVICES TABLE
 *
 * This migration creates the devices table for tracking registered devices
 * (mobile, desktop, CLI) within workspaces. Supports the device registration
 * and E2E encryption key storage for the Nexus protocol.
 *
 * Tables:
 * - devices: Stores device registration data, public keys, and connection status
 *
 * Enums:
 * - device_type: mobile, desktop, cli
 * - device_connection_status: online, offline
 */

-- Create device type enum
CREATE TYPE "public"."device_type" AS ENUM ('mobile', 'desktop', 'cli');

-- Create device connection status enum
CREATE TYPE "public"."device_connection_status" AS ENUM ('online', 'offline');

-- Create devices table
CREATE TABLE "public"."devices" (
  "id" UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  "workspace_id" UUID NOT NULL REFERENCES "public"."workspaces"("id") ON DELETE CASCADE,
  "user_id" UUID NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,
  "device_type" "public"."device_type" NOT NULL,
  "device_name" VARCHAR NOT NULL,
  "device_fingerprint" VARCHAR NOT NULL,
  "public_key" TEXT,
  "connection_status" "public"."device_connection_status" DEFAULT 'offline'::"public"."device_connection_status" NOT NULL,
  "last_seen" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

COMMENT ON TABLE "public"."devices" IS 'Registered devices (mobile, desktop, CLI) for E2E encrypted communication within workspaces.';

ALTER TABLE "public"."devices" OWNER TO "postgres";

-- Create indexes
CREATE INDEX idx_devices_workspace_id ON "public"."devices"("workspace_id");
CREATE INDEX idx_devices_user_id ON "public"."devices"("user_id");
CREATE INDEX idx_devices_fingerprint ON "public"."devices"("device_fingerprint");

-- Unique constraint: one device fingerprint per workspace
CREATE UNIQUE INDEX idx_devices_workspace_fingerprint ON "public"."devices"("workspace_id", "device_fingerprint");

-- Enable Row Level Security
ALTER TABLE "public"."devices" ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- SELECT: Workspace members can view devices in their workspace
CREATE POLICY "Workspace members can view devices" ON "public"."devices"
FOR SELECT TO authenticated
USING (
  "public"."is_workspace_member"((SELECT auth.uid()), "workspace_id")
);

-- INSERT: Workspace members can register their own devices
CREATE POLICY "Workspace members can register devices" ON "public"."devices"
FOR INSERT TO authenticated
WITH CHECK (
  "public"."is_workspace_member"((SELECT auth.uid()), "workspace_id")
  AND (SELECT auth.uid()) = "user_id"
);

-- UPDATE: Users can only update their own devices
CREATE POLICY "Users can update their own devices" ON "public"."devices"
FOR UPDATE TO authenticated
USING ((SELECT auth.uid()) = "user_id")
WITH CHECK ((SELECT auth.uid()) = "user_id");

-- DELETE: Users can delete their own devices, admins can delete any device in workspace
CREATE POLICY "Users can delete their own devices or admins can delete any" ON "public"."devices"
FOR DELETE TO authenticated
USING (
  (SELECT auth.uid()) = "user_id"
  OR "public"."is_workspace_admin"((SELECT auth.uid()), "workspace_id")
);
