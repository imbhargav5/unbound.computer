/*
 * CLAUDE RUNS TABLE
 *
 * Tracks active Claude Code runs for multi-viewer fan-out.
 * Each run is associated with an executor device and can have multiple viewers.
 * Part of NEX-615: Multi-Viewer Fan-out Schema
 */

CREATE TABLE IF NOT EXISTS "public"."claude_runs" (
  "id" UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  "user_id" UUID NOT NULL REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE,

  -- The device executing Claude Code
  "executor_device_id" UUID NOT NULL REFERENCES "public"."devices"("id") ON DELETE CASCADE,

  -- Associated coding session (optional, may be standalone run)
  "coding_session_id" UUID REFERENCES "public"."coding_sessions"("id") ON DELETE SET NULL,

  -- Run identification
  "run_token_hash" TEXT NOT NULL,  -- SHA-256 hash of run token for lookup

  -- Run status
  "status" "public"."coding_session_status" DEFAULT 'active'::"public"."coding_session_status" NOT NULL,

  -- Timestamps
  "started_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  "ended_at" TIMESTAMP WITH TIME ZONE,
  "last_activity_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

  -- Metadata
  "run_metadata" JSONB DEFAULT '{}'::jsonb NOT NULL
);

COMMENT ON TABLE "public"."claude_runs" IS 'Active Claude Code runs for multi-viewer streaming. Executor broadcasts to viewers.';

ALTER TABLE "public"."claude_runs" OWNER TO postgres;

-- Indexes
CREATE INDEX idx_claude_runs_user_id ON "public"."claude_runs"("user_id");
CREATE INDEX idx_claude_runs_executor_device ON "public"."claude_runs"("executor_device_id");
CREATE INDEX idx_claude_runs_coding_session ON "public"."claude_runs"("coding_session_id");
CREATE INDEX idx_claude_runs_token_hash ON "public"."claude_runs"("run_token_hash");
CREATE INDEX idx_claude_runs_status ON "public"."claude_runs"("status");
CREATE INDEX idx_claude_runs_active ON "public"."claude_runs"("user_id", "status")
  WHERE "status" = 'active';
CREATE INDEX idx_claude_runs_last_activity ON "public"."claude_runs"("last_activity_at");

-- Enable Realtime for status updates
ALTER PUBLICATION supabase_realtime ADD TABLE ONLY "public"."claude_runs";

-- Enable RLS
ALTER TABLE "public"."claude_runs" ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own runs" ON "public"."claude_runs"
  FOR SELECT TO authenticated
  USING ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can create runs from their devices" ON "public"."claude_runs"
  FOR INSERT TO authenticated
  WITH CHECK (
    "user_id" = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM "public"."devices"
      WHERE "id" = "executor_device_id"
        AND "user_id" = (SELECT auth.uid())
        AND "is_active" = TRUE
    )
  );

CREATE POLICY "Users can update their own runs" ON "public"."claude_runs"
  FOR UPDATE TO authenticated
  USING ("user_id" = (SELECT auth.uid()))
  WITH CHECK ("user_id" = (SELECT auth.uid()));

CREATE POLICY "Users can delete their own runs" ON "public"."claude_runs"
  FOR DELETE TO authenticated
  USING ("user_id" = (SELECT auth.uid()));

-- Function to end stale runs (no activity for 5 minutes)
CREATE OR REPLACE FUNCTION "public"."cleanup_stale_claude_runs"()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  ended_count INTEGER;
BEGIN
  WITH ended AS (
    UPDATE "public"."claude_runs"
    SET
      "status" = 'ended'::"public"."coding_session_status",
      "ended_at" = NOW()
    WHERE "status" = 'active'
      AND "last_activity_at" < NOW() - INTERVAL '5 minutes'
    RETURNING "id"
  )
  SELECT COUNT(*) INTO ended_count FROM ended;

  RETURN ended_count;
END;
$$;

COMMENT ON FUNCTION "public"."cleanup_stale_claude_runs"() IS 'Ends Claude runs that have been inactive for more than 5 minutes.';
