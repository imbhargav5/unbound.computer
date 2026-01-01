/*
 * TRUST HELPER FUNCTIONS
 *
 * Utility functions for device trust management.
 * Part of NEX-614: Trust Architecture Schema Migrations
 */

-- Check if a device is trusted (has active trust relationship)
CREATE OR REPLACE FUNCTION "public"."is_device_trusted"(
  "p_user_id" UUID,
  "p_device_id" UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_trusted BOOLEAN;
BEGIN
  -- Check if device is the primary trust root
  SELECT EXISTS (
    SELECT 1 FROM "public"."devices"
    WHERE "id" = p_device_id
      AND "user_id" = p_user_id
      AND "is_primary_trust_root" = TRUE
      AND "is_active" = TRUE
  ) INTO v_is_trusted;

  IF v_is_trusted THEN
    RETURN TRUE;
  END IF;

  -- Check if device has active trust relationship
  SELECT EXISTS (
    SELECT 1 FROM "public"."device_trust_graph"
    WHERE "grantee_device_id" = p_device_id
      AND "user_id" = p_user_id
      AND "status" = 'active'
      AND ("expires_at" IS NULL OR "expires_at" > NOW())
  ) INTO v_is_trusted;

  RETURN v_is_trusted;
END;
$$;

ALTER FUNCTION "public"."is_device_trusted"(UUID, UUID) OWNER TO postgres;
COMMENT ON FUNCTION "public"."is_device_trusted"(UUID, UUID) IS 'Checks if a device is trusted (primary trust root or has active trust relationship).';

-- Get the trust chain for a device (path from trust root to device)
CREATE OR REPLACE FUNCTION "public"."get_device_trust_chain"(
  "p_device_id" UUID
)
RETURNS TABLE(
  "device_id" UUID,
  "device_name" TEXT,
  "device_role" "public"."device_role",
  "trust_level" INTEGER,
  "grantor_device_id" UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE trust_chain AS (
    -- Base case: the device itself
    SELECT
      d."id" AS device_id,
      d."name" AS device_name,
      d."device_role",
      0 AS trust_level,
      NULL::UUID AS grantor_device_id,
      d."user_id"
    FROM "public"."devices" d
    WHERE d."id" = p_device_id

    UNION ALL

    -- Recursive case: find grantor devices
    SELECT
      g."id" AS device_id,
      g."name" AS device_name,
      g."device_role",
      tc.trust_level + 1 AS trust_level,
      dtg."grantor_device_id",
      g."user_id"
    FROM trust_chain tc
    JOIN "public"."device_trust_graph" dtg ON dtg."grantee_device_id" = tc.device_id
    JOIN "public"."devices" g ON g."id" = dtg."grantor_device_id"
    WHERE dtg."status" = 'active'
      AND (dtg."expires_at" IS NULL OR dtg."expires_at" > NOW())
      AND tc.trust_level < 3  -- Max depth
  )
  SELECT
    tc.device_id,
    tc.device_name,
    tc.device_role,
    tc.trust_level,
    tc.grantor_device_id
  FROM trust_chain tc
  ORDER BY tc.trust_level ASC;
END;
$$;

ALTER FUNCTION "public"."get_device_trust_chain"(UUID) OWNER TO postgres;
COMMENT ON FUNCTION "public"."get_device_trust_chain"(UUID) IS 'Returns the trust chain from a device up to the trust root.';

-- Revoke trust for a device (cascades to devices it introduced)
CREATE OR REPLACE FUNCTION "public"."revoke_device_trust"(
  "p_device_id" UUID,
  "p_reason" TEXT DEFAULT 'manually_revoked'
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_revoked_count INTEGER := 0;
BEGIN
  -- Get the user ID and verify ownership
  SELECT "user_id" INTO v_user_id
  FROM "public"."devices"
  WHERE "id" = p_device_id;

  IF v_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to revoke trust for this device';
  END IF;

  -- Revoke all trust relationships where this device is the grantee
  WITH revoked AS (
    UPDATE "public"."device_trust_graph"
    SET
      "status" = 'revoked'::"public"."trust_relationship_status",
      "revoked_at" = NOW(),
      "revoked_reason" = p_reason
    WHERE "grantee_device_id" = p_device_id
      AND "status" = 'active'
    RETURNING "id"
  )
  SELECT COUNT(*) INTO v_revoked_count FROM revoked;

  -- Cascade: revoke trust for devices that this device introduced
  WITH RECURSIVE cascade_revoke AS (
    -- Devices directly introduced by the revoked device
    SELECT "grantee_device_id" AS device_id
    FROM "public"."device_trust_graph"
    WHERE "grantor_device_id" = p_device_id
      AND "status" = 'active'

    UNION ALL

    -- Recursively find devices introduced by those devices
    SELECT dtg."grantee_device_id"
    FROM "public"."device_trust_graph" dtg
    JOIN cascade_revoke cr ON dtg."grantor_device_id" = cr.device_id
    WHERE dtg."status" = 'active'
  ),
  cascade_updated AS (
    UPDATE "public"."device_trust_graph" dtg
    SET
      "status" = 'revoked'::"public"."trust_relationship_status",
      "revoked_at" = NOW(),
      "revoked_reason" = 'cascade_from_' || p_device_id::TEXT
    FROM cascade_revoke cr
    WHERE dtg."grantee_device_id" = cr.device_id
      AND dtg."status" = 'active'
    RETURNING dtg."id"
  )
  SELECT v_revoked_count + COUNT(*) INTO v_revoked_count FROM cascade_updated;

  -- Deactivate the device itself
  UPDATE "public"."devices"
  SET
    "is_active" = FALSE,
    "updated_at" = NOW()
  WHERE "id" = p_device_id;

  RETURN v_revoked_count;
END;
$$;

ALTER FUNCTION "public"."revoke_device_trust"(UUID, TEXT) OWNER TO postgres;
COMMENT ON FUNCTION "public"."revoke_device_trust"(UUID, TEXT) IS 'Revokes trust for a device and cascades to all devices it introduced.';

-- Get all devices for a user with their trust status
CREATE OR REPLACE FUNCTION "public"."get_user_devices_with_trust"()
RETURNS TABLE(
  "id" UUID,
  "name" TEXT,
  "device_type" "public"."device_type",
  "device_role" "public"."device_role",
  "is_primary_trust_root" BOOLEAN,
  "is_trusted" BOOLEAN,
  "trust_level" INTEGER,
  "verified_at" TIMESTAMP WITH TIME ZONE,
  "last_seen_at" TIMESTAMP WITH TIME ZONE,
  "is_active" BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();

  RETURN QUERY
  SELECT
    d."id",
    d."name",
    d."device_type",
    d."device_role",
    d."is_primary_trust_root",
    COALESCE(
      d."is_primary_trust_root",
      EXISTS (
        SELECT 1 FROM "public"."device_trust_graph" dtg
        WHERE dtg."grantee_device_id" = d."id"
          AND dtg."status" = 'active'
          AND (dtg."expires_at" IS NULL OR dtg."expires_at" > NOW())
      )
    ) AS is_trusted,
    COALESCE(
      (
        SELECT dtg."trust_level"
        FROM "public"."device_trust_graph" dtg
        WHERE dtg."grantee_device_id" = d."id"
          AND dtg."status" = 'active'
        LIMIT 1
      ),
      CASE WHEN d."is_primary_trust_root" THEN 0 ELSE NULL END
    ) AS trust_level,
    d."verified_at",
    d."last_seen_at",
    d."is_active"
  FROM "public"."devices" d
  WHERE d."user_id" = v_user_id
  ORDER BY
    d."is_primary_trust_root" DESC,
    d."device_role",
    d."last_seen_at" DESC NULLS LAST;
END;
$$;

ALTER FUNCTION "public"."get_user_devices_with_trust"() OWNER TO postgres;
COMMENT ON FUNCTION "public"."get_user_devices_with_trust"() IS 'Returns all devices for the current user with their trust status and level.';
