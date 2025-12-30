/*
 * DEVICES TABLE
 *
 * Tracks registered devices (Mac, Linux, Windows CLI) for each user.
 * Part of NEX-590: Device Registration Schema and API
 */

CREATE TABLE IF NOT EXISTS public.devices (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4() NOT NULL,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,

  -- Device identification
  name TEXT NOT NULL,
  device_type public.device_type NOT NULL,
  hostname TEXT,
  fingerprint TEXT,

  -- Status tracking
  is_active BOOLEAN DEFAULT true NOT NULL,
  last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

  -- Unique device per user based on fingerprint
  UNIQUE(user_id, fingerprint)
);

COMMENT ON TABLE public.devices IS 'Registered devices (Mac, Linux, Windows) for remote CLI access.';

ALTER TABLE public.devices OWNER TO postgres;

-- Indexes
CREATE INDEX idx_devices_user_id ON public.devices(user_id);
CREATE INDEX idx_devices_is_active ON public.devices(is_active);
CREATE INDEX idx_devices_last_seen ON public.devices(last_seen_at);

-- Enable RLS
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own devices" ON public.devices
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can insert their own devices" ON public.devices
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update their own devices" ON public.devices
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can delete their own devices" ON public.devices
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));
