/*
 * RUN VIEWERS TABLE
 *
 * Tracks viewers connected to Claude runs for multi-viewer fan-out.
 * Each viewer can be a device or web session with specific permissions.
 * Part of NEX-615: Multi-Viewer Fan-out Schema
 */

CREATE TABLE IF NOT EXISTS "public"."run_viewers" (
  "id" UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  "run_id" UUID NOT NULL REFERENCES "public"."claude_runs"("id") ON DELETE CASCADE,

  -- Viewer can be a device OR a web session (exactly one must be set)
  "viewer_device_id" UUID REFERENCES "public"."devices"("id") ON DELETE CASCADE,
  "viewer_web_session_id" UUID REFERENCES "public"."web_sessions"("id") ON DELETE CASCADE,

  -- Permission level for this viewer
  "permission" "public"."web_session_permission" DEFAULT 'view_only'::"public"."web_session_permission" NOT NULL,

  -- Viewer status
  "is_active" BOOLEAN DEFAULT TRUE NOT NULL,
  "joined_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  "left_at" TIMESTAMP WITH TIME ZONE,
  "last_seen_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

  -- Encryption context (viewer's session-specific public key)
  "viewer_session_public_key" TEXT,

  -- Ensure exactly one viewer type is set
  CONSTRAINT "run_viewers_exactly_one_viewer" CHECK (
    (("viewer_device_id" IS NOT NULL)::INTEGER + ("viewer_web_session_id" IS NOT NULL)::INTEGER) = 1
  )
);

COMMENT ON TABLE "public"."run_viewers" IS 'Viewers connected to Claude runs. Supports both device and web session viewers.';

ALTER TABLE "public"."run_viewers" OWNER TO postgres;

-- Indexes
CREATE INDEX idx_run_viewers_run_id ON "public"."run_viewers"("run_id");
CREATE INDEX idx_run_viewers_device ON "public"."run_viewers"("viewer_device_id");
CREATE INDEX idx_run_viewers_web_session ON "public"."run_viewers"("viewer_web_session_id");
CREATE INDEX idx_run_viewers_active ON "public"."run_viewers"("run_id", "is_active")
  WHERE "is_active" = TRUE;

-- Unique viewer per run (prevent duplicate connections)
CREATE UNIQUE INDEX idx_run_viewers_unique_device ON "public"."run_viewers"("run_id", "viewer_device_id")
  WHERE "viewer_device_id" IS NOT NULL AND "is_active" = TRUE;
CREATE UNIQUE INDEX idx_run_viewers_unique_web_session ON "public"."run_viewers"("run_id", "viewer_web_session_id")
  WHERE "viewer_web_session_id" IS NOT NULL AND "is_active" = TRUE;

-- Enable Realtime for viewer updates
ALTER PUBLICATION supabase_realtime ADD TABLE ONLY "public"."run_viewers";

-- Enable RLS
ALTER TABLE "public"."run_viewers" ENABLE ROW LEVEL SECURITY;

-- RLS Policies (viewers can be accessed by run owner)
CREATE POLICY "Run owners can view their run viewers" ON "public"."run_viewers"
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "public"."claude_runs" cr
      WHERE cr."id" = "run_id"
        AND cr."user_id" = (SELECT auth.uid())
    )
  );

CREATE POLICY "Run owners can add viewers" ON "public"."run_viewers"
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM "public"."claude_runs" cr
      WHERE cr."id" = "run_id"
        AND cr."user_id" = (SELECT auth.uid())
    )
  );

CREATE POLICY "Run owners can update viewers" ON "public"."run_viewers"
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "public"."claude_runs" cr
      WHERE cr."id" = "run_id"
        AND cr."user_id" = (SELECT auth.uid())
    )
  );

CREATE POLICY "Run owners can remove viewers" ON "public"."run_viewers"
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "public"."claude_runs" cr
      WHERE cr."id" = "run_id"
        AND cr."user_id" = (SELECT auth.uid())
    )
  );

-- Function to get active viewers for a run
CREATE OR REPLACE FUNCTION "public"."get_run_active_viewers"(
  "p_run_id" UUID
)
RETURNS TABLE(
  "viewer_id" UUID,
  "viewer_type" TEXT,
  "viewer_name" TEXT,
  "permission" "public"."web_session_permission",
  "joined_at" TIMESTAMP WITH TIME ZONE,
  "last_seen_at" TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Verify the user owns this run
  IF NOT EXISTS (
    SELECT 1 FROM "public"."claude_runs"
    WHERE "id" = p_run_id AND "user_id" = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this run';
  END IF;

  RETURN QUERY
  SELECT
    rv."id" AS viewer_id,
    CASE
      WHEN rv."viewer_device_id" IS NOT NULL THEN 'device'
      ELSE 'web_session'
    END AS viewer_type,
    COALESCE(
      d."name",
      'Web Session'
    ) AS viewer_name,
    rv."permission",
    rv."joined_at",
    rv."last_seen_at"
  FROM "public"."run_viewers" rv
  LEFT JOIN "public"."devices" d ON d."id" = rv."viewer_device_id"
  WHERE rv."run_id" = p_run_id
    AND rv."is_active" = TRUE
  ORDER BY rv."joined_at" ASC;
END;
$$;

COMMENT ON FUNCTION "public"."get_run_active_viewers"(UUID) IS 'Returns all active viewers for a Claude run.';
