-- Async billing usage metering primitives:
-- 1) immutable usage event log with request_id idempotency
-- 2) aggregated counters per customer/period
-- 3) atomic recorder function used by trusted server paths

CREATE TABLE IF NOT EXISTS public.billing_usage_events (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    gateway_name text NOT NULL,
    gateway_customer_id text NOT NULL,
    usage_type text NOT NULL,
    request_id text NOT NULL,
    quantity integer NOT NULL DEFAULT 1,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    event_timestamp timestamp with time zone NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT billing_usage_events_quantity_positive CHECK (quantity > 0),
    CONSTRAINT billing_usage_events_period_valid CHECK (period_end > period_start),
    CONSTRAINT billing_usage_events_gateway_request_unique UNIQUE (gateway_name, request_id),
    CONSTRAINT billing_usage_events_gateway_customer_id_fkey
      FOREIGN KEY (gateway_customer_id)
      REFERENCES public.billing_customers(gateway_customer_id)
      ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_billing_usage_events_customer_timestamp
  ON public.billing_usage_events (gateway_customer_id, event_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_billing_usage_events_usage_type_period
  ON public.billing_usage_events (usage_type, period_start, period_end);

CREATE TABLE IF NOT EXISTS public.billing_usage_counters (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    gateway_name text NOT NULL,
    gateway_customer_id text NOT NULL,
    usage_type text NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    usage_count bigint NOT NULL DEFAULT 0,
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT billing_usage_counters_non_negative CHECK (usage_count >= 0),
    CONSTRAINT billing_usage_counters_period_valid CHECK (period_end > period_start),
    CONSTRAINT billing_usage_counters_unique
      UNIQUE (gateway_name, gateway_customer_id, usage_type, period_start, period_end),
    CONSTRAINT billing_usage_counters_gateway_customer_id_fkey
      FOREIGN KEY (gateway_customer_id)
      REFERENCES public.billing_customers(gateway_customer_id)
      ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_billing_usage_counters_customer_type_period
  ON public.billing_usage_counters (gateway_customer_id, usage_type, period_start, period_end);

CREATE OR REPLACE FUNCTION public.record_billing_usage_event(
  p_gateway_name text,
  p_gateway_customer_id text,
  p_usage_type text,
  p_request_id text,
  p_period_start timestamp with time zone,
  p_period_end timestamp with time zone,
  p_quantity integer DEFAULT 1,
  p_event_timestamp timestamp with time zone DEFAULT now(),
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS public.billing_usage_counters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  inserted_event_id uuid;
  counter_row public.billing_usage_counters;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'p_quantity must be > 0';
  END IF;

  IF p_period_end <= p_period_start THEN
    RAISE EXCEPTION 'period_end must be after period_start';
  END IF;

  INSERT INTO public.billing_usage_events (
    gateway_name,
    gateway_customer_id,
    usage_type,
    request_id,
    quantity,
    period_start,
    period_end,
    event_timestamp,
    metadata
  )
  VALUES (
    p_gateway_name,
    p_gateway_customer_id,
    p_usage_type,
    p_request_id,
    p_quantity,
    p_period_start,
    p_period_end,
    p_event_timestamp,
    COALESCE(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (gateway_name, request_id) DO NOTHING
  RETURNING id INTO inserted_event_id;

  IF inserted_event_id IS NULL THEN
    SELECT *
      INTO counter_row
      FROM public.billing_usage_counters
     WHERE gateway_name = p_gateway_name
       AND gateway_customer_id = p_gateway_customer_id
       AND usage_type = p_usage_type
       AND period_start = p_period_start
       AND period_end = p_period_end;
    RETURN counter_row;
  END IF;

  INSERT INTO public.billing_usage_counters (
    gateway_name,
    gateway_customer_id,
    usage_type,
    period_start,
    period_end,
    usage_count
  )
  VALUES (
    p_gateway_name,
    p_gateway_customer_id,
    p_usage_type,
    p_period_start,
    p_period_end,
    p_quantity
  )
  ON CONFLICT (gateway_name, gateway_customer_id, usage_type, period_start, period_end)
  DO UPDATE SET
    usage_count = public.billing_usage_counters.usage_count + EXCLUDED.usage_count,
    updated_at = now()
  RETURNING * INTO counter_row;

  RETURN counter_row;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_billing_usage_event(
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  integer,
  timestamp with time zone,
  jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_billing_usage_event(
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  integer,
  timestamp with time zone,
  jsonb
) TO service_role;

ALTER TABLE public.billing_usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_usage_counters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own billing usage events"
  ON public.billing_usage_events
  FOR SELECT
  USING (public.get_customer_user_id(gateway_customer_id) = auth.uid());

CREATE POLICY "Users can view their own billing usage counters"
  ON public.billing_usage_counters
  FOR SELECT
  USING (public.get_customer_user_id(gateway_customer_id) = auth.uid());

GRANT SELECT ON public.billing_usage_events TO authenticated;
GRANT SELECT ON public.billing_usage_counters TO authenticated;
GRANT ALL ON public.billing_usage_events TO service_role;
GRANT ALL ON public.billing_usage_counters TO service_role;
