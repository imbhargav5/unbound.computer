/*
 * REPOSITORY & SESSION ENUMS
 *
 * Enum types for repository and coding session tracking.
 */

-- Repository status for visibility/archival
CREATE TYPE public.repository_status AS ENUM ('active', 'archived');

-- Coding session status
CREATE TYPE public.coding_session_status AS ENUM ('active', 'paused', 'ended');

-- Device type enum
CREATE TYPE public.device_type AS ENUM ('mac', 'linux', 'windows', 'cli');
