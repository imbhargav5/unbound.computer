/*
 * TRUST ARCHITECTURE ENUMS
 *
 * Enum types for device-rooted trust model.
 * Part of NEX-614: Trust Architecture Schema Migrations
 */

-- Device role in the trust hierarchy
-- trust_root: Phone (iOS) - introduces devices, approves web sessions
-- trusted_executor: Mac/Desktop - runs Claude Code, streams to viewers
-- temporary_viewer: Web - gets short-lived session key
CREATE TYPE "public"."device_role" AS ENUM (
  'trust_root',
  'trusted_executor',
  'temporary_viewer'
);

-- Trust relationship status between devices
CREATE TYPE "public"."trust_relationship_status" AS ENUM (
  'pending',
  'active',
  'revoked',
  'expired'
);

-- Web session permission levels
CREATE TYPE "public"."web_session_permission" AS ENUM (
  'view_only',
  'interact',
  'full_control'
);

-- Add 'phone' and 'web' to existing device_type enum
ALTER TYPE "public"."device_type" ADD VALUE IF NOT EXISTS 'phone';
ALTER TYPE "public"."device_type" ADD VALUE IF NOT EXISTS 'web';
