ALTER TABLE public.devices
ADD COLUMN IF NOT EXISTS capabilities jsonb DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.devices.capabilities IS
'Canonical device capabilities payload. See docs/device-capabilities.md for schema.';
