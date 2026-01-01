/*
 * WEB SESSIONS TRUST ENHANCEMENTS
 *
 * Add permission levels and TTL controls to web sessions.
 * Part of NEX-615: Multi-Viewer Fan-out Schema
 */

-- Add permission level column
ALTER TABLE "public"."web_sessions"
  ADD COLUMN IF NOT EXISTS "permission" "public"."web_session_permission"
  DEFAULT 'view_only'::"public"."web_session_permission" NOT NULL;

-- Add max idle time (seconds before session expires due to inactivity)
ALTER TABLE "public"."web_sessions"
  ADD COLUMN IF NOT EXISTS "max_idle_seconds" INTEGER DEFAULT 1800 NOT NULL;  -- 30 minutes

-- Add session TTL (total max lifetime in seconds)
ALTER TABLE "public"."web_sessions"
  ADD COLUMN IF NOT EXISTS "session_ttl_seconds" INTEGER DEFAULT 86400 NOT NULL;  -- 24 hours

-- Add authorizing device public key for encryption
ALTER TABLE "public"."web_sessions"
  ADD COLUMN IF NOT EXISTS "authorizing_device_public_key" TEXT;

-- Add comments
COMMENT ON COLUMN "public"."web_sessions"."permission" IS 'Permission level: view_only, interact, or full_control';
COMMENT ON COLUMN "public"."web_sessions"."max_idle_seconds" IS 'Max idle time in seconds before session expires (default 30 min)';
COMMENT ON COLUMN "public"."web_sessions"."session_ttl_seconds" IS 'Total session lifetime in seconds (default 24 hours)';
COMMENT ON COLUMN "public"."web_sessions"."authorizing_device_public_key" IS 'Long-term public key of authorizing device for trust verification';

-- Index for permission-based queries
CREATE INDEX IF NOT EXISTS idx_web_sessions_permission
  ON "public"."web_sessions"("permission");

-- Update authorize_web_session function to include permission
CREATE OR REPLACE FUNCTION "public"."authorize_web_session_v2"(
  "p_session_id" UUID,
  "p_device_id" UUID,
  "p_encrypted_session_key" TEXT,
  "p_responder_public_key" TEXT,
  "p_permission" "public"."web_session_permission" DEFAULT 'view_only'::"public"."web_session_permission",
  "p_session_ttl_seconds" INTEGER DEFAULT 86400,
  "p_max_idle_seconds" INTEGER DEFAULT 1800
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_session_user_id UUID;
  v_session_status "public"."web_session_status";
  v_device_public_key TEXT;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();

  -- Verify the session exists and is pending
  SELECT "user_id", "status" INTO v_session_user_id, v_session_status
  FROM "public"."web_sessions"
  WHERE "id" = p_session_id;

  IF v_session_user_id IS NULL THEN
    RAISE EXCEPTION 'Web session not found';
  END IF;

  IF v_session_user_id != v_user_id THEN
    RAISE EXCEPTION 'Not authorized to authorize this session';
  END IF;

  IF v_session_status != 'pending' THEN
    RAISE EXCEPTION 'Session is not in pending state';
  END IF;

  -- Verify the device belongs to the user and get its public key
  SELECT "public_key" INTO v_device_public_key
  FROM "public"."devices"
  WHERE "id" = p_device_id
    AND "user_id" = v_user_id
    AND "is_active" = TRUE;

  IF v_device_public_key IS NULL AND NOT EXISTS (
    SELECT 1 FROM "public"."devices"
    WHERE "id" = p_device_id AND "user_id" = v_user_id AND "is_active" = TRUE
  ) THEN
    RAISE EXCEPTION 'Device not found or not active';
  END IF;

  -- Authorize the session
  UPDATE "public"."web_sessions"
  SET
    "status" = 'active',
    "authorizing_device_id" = p_device_id,
    "encrypted_session_key" = p_encrypted_session_key,
    "responder_public_key" = p_responder_public_key,
    "authorizing_device_public_key" = v_device_public_key,
    "permission" = p_permission,
    "session_ttl_seconds" = p_session_ttl_seconds,
    "max_idle_seconds" = p_max_idle_seconds,
    "authorized_at" = NOW(),
    "expires_at" = NOW() + (p_session_ttl_seconds || ' seconds')::INTERVAL,
    "last_activity_at" = NOW()
  WHERE "id" = p_session_id;

  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION "public"."authorize_web_session_v2"(UUID, UUID, TEXT, TEXT, "public"."web_session_permission", INTEGER, INTEGER)
  IS 'Authorizes a pending web session with permission level and TTL controls.';

-- Function to check if web session is still valid (respects idle timeout)
CREATE OR REPLACE FUNCTION "public"."is_web_session_valid"(
  "p_session_id" UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_session RECORD;
BEGIN
  SELECT
    "status",
    "expires_at",
    "last_activity_at",
    "max_idle_seconds"
  INTO v_session
  FROM "public"."web_sessions"
  WHERE "id" = p_session_id
    AND "user_id" = auth.uid();

  IF v_session IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Check status
  IF v_session.status != 'active' THEN
    RETURN FALSE;
  END IF;

  -- Check absolute expiry
  IF v_session.expires_at < NOW() THEN
    RETURN FALSE;
  END IF;

  -- Check idle timeout
  IF v_session.last_activity_at + (v_session.max_idle_seconds || ' seconds')::INTERVAL < NOW() THEN
    -- Mark as expired
    UPDATE "public"."web_sessions"
    SET "status" = 'expired'
    WHERE "id" = p_session_id;
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION "public"."is_web_session_valid"(UUID) IS 'Checks if a web session is still valid (active, not expired, not idle timeout).';
