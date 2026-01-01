/*
 * WEB SESSIONS TABLE
 *
 * Tracks browser-based sessions for secure web access.
 * Uses QR-based device authorization similar to WhatsApp Web.
 * Part of NEX-606: Web Session Database Schema
 */

-- Web session status enum
CREATE TYPE public.web_session_status AS ENUM (
  'pending',    -- Awaiting device authorization
  'active',     -- Authorized and active
  'expired',    -- Time expired
  'revoked'     -- Manually revoked
);

CREATE TABLE IF NOT EXISTS public.web_sessions (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,

  -- Authorizing device (null until authorized)
  authorizing_device_id UUID REFERENCES public.devices(id) ON DELETE SET NULL,

  -- Session security
  session_token_hash TEXT NOT NULL,           -- SHA-256 hash of session token
  web_public_key TEXT NOT NULL,               -- Web client's ephemeral X25519 public key (base64)
  encrypted_session_key TEXT,                 -- Session key encrypted with web's pubkey (base64)
  responder_public_key TEXT,                  -- Authorizing device's ephemeral public key (base64)

  -- Metadata
  user_agent TEXT,
  ip_address INET,
  browser_fingerprint TEXT,                   -- Optional browser fingerprint for security

  -- Lifecycle
  status public.web_session_status DEFAULT 'pending' NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  authorized_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Audit
  revoked_at TIMESTAMP WITH TIME ZONE,
  revoked_reason TEXT
);

COMMENT ON TABLE public.web_sessions IS 'Browser-based sessions with QR-based device authorization for secure web access.';

ALTER TABLE public.web_sessions OWNER TO postgres;

-- Indexes for common queries
CREATE INDEX idx_web_sessions_user_id ON public.web_sessions(user_id);
CREATE INDEX idx_web_sessions_session_token_hash ON public.web_sessions(session_token_hash);
CREATE INDEX idx_web_sessions_status ON public.web_sessions(status);
CREATE INDEX idx_web_sessions_expires_at ON public.web_sessions(expires_at);
CREATE INDEX idx_web_sessions_user_status ON public.web_sessions(user_id, status);
CREATE INDEX idx_web_sessions_authorizing_device ON public.web_sessions(authorizing_device_id);

-- Enable Realtime for status updates (web client polls for authorization)
ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.web_sessions;

-- Enable RLS
ALTER TABLE public.web_sessions ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Users can view their own web sessions
CREATE POLICY "Users can view their own web sessions" ON public.web_sessions
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Users can create their own web sessions
CREATE POLICY "Users can create their own web sessions" ON public.web_sessions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Users can update their own web sessions (for authorization and revocation)
CREATE POLICY "Users can update their own web sessions" ON public.web_sessions
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Users can delete their own web sessions
CREATE POLICY "Users can delete their own web sessions" ON public.web_sessions
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Function to clean up expired pending sessions
CREATE OR REPLACE FUNCTION public.cleanup_expired_web_sessions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  WITH deleted AS (
    DELETE FROM public.web_sessions
    WHERE status = 'pending'
      AND expires_at < NOW()
    RETURNING id
  )
  SELECT COUNT(*) INTO deleted_count FROM deleted;

  -- Also mark expired active sessions
  UPDATE public.web_sessions
  SET status = 'expired'
  WHERE status = 'active'
    AND expires_at < NOW();

  RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_expired_web_sessions() IS 'Cleans up expired pending web sessions and marks expired active sessions.';

-- Function to authorize a web session (called by trusted device)
CREATE OR REPLACE FUNCTION public.authorize_web_session(
  p_session_id UUID,
  p_device_id UUID,
  p_encrypted_session_key TEXT,
  p_responder_public_key TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_session_user_id UUID;
  v_session_status public.web_session_status;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();

  -- Verify the session exists and is pending
  SELECT user_id, status INTO v_session_user_id, v_session_status
  FROM public.web_sessions
  WHERE id = p_session_id;

  IF v_session_user_id IS NULL THEN
    RAISE EXCEPTION 'Web session not found';
  END IF;

  IF v_session_user_id != v_user_id THEN
    RAISE EXCEPTION 'Not authorized to authorize this session';
  END IF;

  IF v_session_status != 'pending' THEN
    RAISE EXCEPTION 'Session is not in pending state';
  END IF;

  -- Verify the device belongs to the user
  IF NOT EXISTS (
    SELECT 1 FROM public.devices
    WHERE id = p_device_id AND user_id = v_user_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Device not found or not active';
  END IF;

  -- Authorize the session
  UPDATE public.web_sessions
  SET
    status = 'active',
    authorizing_device_id = p_device_id,
    encrypted_session_key = p_encrypted_session_key,
    responder_public_key = p_responder_public_key,
    authorized_at = NOW(),
    expires_at = NOW() + INTERVAL '24 hours',  -- Extend to 24 hours after authorization
    last_activity_at = NOW()
  WHERE id = p_session_id;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.authorize_web_session(UUID, UUID, TEXT, TEXT) IS 'Authorizes a pending web session from a trusted device.';

-- Function to revoke a web session
CREATE OR REPLACE FUNCTION public.revoke_web_session(
  p_session_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();

  UPDATE public.web_sessions
  SET
    status = 'revoked',
    revoked_at = NOW(),
    revoked_reason = p_reason
  WHERE id = p_session_id
    AND user_id = v_user_id
    AND status IN ('pending', 'active');

  RETURN FOUND;
END;
$$;

COMMENT ON FUNCTION public.revoke_web_session(UUID, TEXT) IS 'Revokes an active or pending web session.';

-- Function to update last activity (extends session on activity)
CREATE OR REPLACE FUNCTION public.touch_web_session(p_session_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.web_sessions
  SET last_activity_at = NOW()
  WHERE id = p_session_id
    AND user_id = auth.uid()
    AND status = 'active'
    AND expires_at > NOW();

  RETURN FOUND;
END;
$$;

COMMENT ON FUNCTION public.touch_web_session(UUID) IS 'Updates last activity timestamp for a web session.';
