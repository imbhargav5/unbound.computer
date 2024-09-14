-- Plans table
CREATE TABLE IF NOT EXISTS public.billing_plans (
  gateway_plan_id TEXT PRIMARY KEY,
  gateway_name TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  is_subscription BOOLEAN NOT NULL,
  free_trial_days INT,
  features JSONB,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  is_visible_in_ui BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE(gateway_name, gateway_plan_id)
);

CREATE INDEX idx_billing_plans_gateway_name ON public.billing_plans(gateway_name);
CREATE INDEX idx_billing_plans_gateway_plan_id ON public.billing_plans(gateway_plan_id);

-- Plan Prices table
CREATE TABLE IF NOT EXISTS public.billing_plan_prices (
  gateway_price_id TEXT PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway_plan_id TEXT NOT NULL REFERENCES public.billing_plans(gateway_plan_id),
  currency TEXT NOT NULL,
  amount DECIMAL NOT NULL,
  recurring_interval TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  tier TEXT,
  gateway_name TEXT NOT NULL
);


-- Volume Tiers table
CREATE TABLE IF NOT EXISTS public.billing_volume_tiers (
  "id" "uuid" PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_price_id TEXT NOT NULL REFERENCES public.billing_plan_prices(gateway_price_id),
  min_quantity INT NOT NULL,
  max_quantity INT,
  unit_price DECIMAL NOT NULL
);

-- Customers table
CREATE TABLE IF NOT EXISTS public.billing_customers (
  gateway_customer_id TEXT PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id),
  gateway_name TEXT NOT NULL,
  gateway_plan_id TEXT REFERENCES public.billing_plans(gateway_plan_id),
  default_currency TEXT,
  billing_email TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  UNIQUE (workspace_id, gateway_name)
);

CREATE INDEX idx_billing_customers_gateway_plan_id ON public.billing_customers(gateway_plan_id);
CREATE INDEX idx_billing_customers_workspace ON public.billing_customers(workspace_id);

-- Subscriptions table
CREATE TABLE IF NOT EXISTS public.billing_subscriptions (
  id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_customer_id TEXT NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  gateway_name TEXT NOT NULL,
  gateway_subscription_id TEXT NOT NULL,
  gateway_plan_id TEXT NOT NULL,
  STATUS public.subscription_status NOT NULL,
  current_period_start DATE NOT NULL,
  current_period_end DATE NOT NULL,
  currency TEXT NOT NULL,
  is_trial BOOLEAN NOT NULL,
  trial_ends_at DATE,
  cancel_at_period_end BOOLEAN NOT NULL,
  quantity INT,
  UNIQUE(gateway_name, gateway_subscription_id)
);

CREATE INDEX idx_billing_subscriptions_customer_id ON public.billing_subscriptions(gateway_customer_id);
CREATE INDEX idx_billing_subscriptions_plan_id ON public.billing_subscriptions(gateway_plan_id);

-- One time payments table
CREATE TABLE IF NOT EXISTS public.billing_one_time_payments (
  id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_customer_id TEXT NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  amount DECIMAL NOT NULL,
  currency TEXT NOT NULL,
  payment_date TIMESTAMP WITH TIME ZONE NOT NULL,
  gateway_plan_id TEXT REFERENCES public.billing_plans(gateway_plan_id)
);

CREATE INDEX idx_billing_one_time_payments_customer_id ON public.billing_one_time_payments(gateway_customer_id);
CREATE INDEX idx_billing_one_time_payments_plan_id ON public.billing_one_time_payments(gateway_plan_id);

-- Charges table
CREATE TABLE IF NOT EXISTS public.billing_charges (
  gateway_charge_id TEXT PRIMARY KEY,
  gateway_name TEXT NOT NULL,
  gateway_customer_id TEXT NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  amount DECIMAL NOT NULL,
  currency TEXT NOT NULL,
  STATUS TEXT NOT NULL,
  charge_date TIMESTAMP WITH TIME ZONE NOT NULL,
  gateway_plan_id TEXT REFERENCES public.billing_plans(gateway_plan_id)
);

CREATE INDEX idx_billing_charges_customer_id ON public.billing_charges(gateway_customer_id);
CREATE INDEX idx_billing_charges_plan_id ON public.billing_charges(gateway_plan_id);
CREATE INDEX idx_billing_charges_gateway_name ON public.billing_charges(gateway_name);

-- payment methods
CREATE TABLE IF NOT EXISTS public.billing_payment_methods (
  id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_customer_id TEXT NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  payment_method_id TEXT NOT NULL,
  payment_method_type TEXT NOT NULL,
  payment_method_details JSONB NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_billing_payment_methods_customer_id ON public.billing_payment_methods(gateway_customer_id);
CREATE INDEX idx_billing_payment_methods_payment_method_id ON public.billing_payment_methods(payment_method_id);
CREATE INDEX idx_billing_payment_methods_payment_method_type ON public.billing_payment_methods(payment_method_type);



-- -- Credit Logs table
-- CREATE TABLE IF NOT EXISTS public.billing_credit_logs (
--   id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
--   gateway_customer_id TEXT NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
--   amount INT NOT NULL,
--   balance_after INT NOT NULL,
--   description TEXT,
--   created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
-- );
-- Invoices table
CREATE TABLE IF NOT EXISTS public.billing_invoices (
  id TEXT PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"()::text NOT NULL,
  gateway_customer_id TEXT NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  amount DECIMAL NOT NULL,
  currency TEXT NOT NULL,
  STATUS TEXT NOT NULL,
  due_date DATE NOT NULL,
  paid_date DATE,
  hosted_invoice_url TEXT
);



-- Usage Logs table
CREATE TABLE IF NOT EXISTS public.billing_usage_logs (
  id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_customer_id TEXT NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  feature TEXT NOT NULL,
  usage_amount INT NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_billing_usage_logs_customer_id ON public.billing_usage_logs(gateway_customer_id);

-- functions
CREATE OR REPLACE FUNCTION "public"."get_customer_workspace_id" (customer_id_arg TEXT) RETURNS UUID LANGUAGE plpgsql
SET search_path = public,
  pg_temp AS $$
DECLARE workspace_id UUID;
BEGIN
SELECT c."workspace_id" INTO workspace_id
FROM "public"."billing_customers" c
WHERE c."gateway_customer_id" = customer_id_arg;
RETURN workspace_id;
END;
$$;


REVOKE ALL ON FUNCTION public.get_customer_workspace_id(TEXT)
FROM anon;
REVOKE ALL ON FUNCTION public.get_customer_workspace_id(TEXT)
FROM authenticated;

-- Add indexes for better query performance
CREATE INDEX idx_billing_plan_prices_plan_id ON public.billing_plan_prices(gateway_plan_id);
CREATE INDEX idx_billing_volume_tiers_plan_price_id ON public.billing_volume_tiers(gateway_price_id);
CREATE INDEX idx_billing_customers_workspace_id_gateway_name ON public.billing_customers(workspace_id, gateway_name);
CREATE INDEX idx_billing_subscriptions_customer_id_gateway_name ON public.billing_subscriptions(gateway_customer_id, gateway_name);
-- CREATE INDEX idx_billing_credit_logs_gateway_customer_id ON public.billing_credit_logs(gateway_customer_id);
CREATE INDEX idx_billing_invoices_gateway_customer_id ON public.billing_invoices(gateway_customer_id);
CREATE INDEX idx_billing_usage_logs_gateway_customer_id ON public.billing_usage_logs(gateway_customer_id);


-- billing tables can only be viewed by authenticated users
REVOKE ALL ON TABLE public.billing_plans
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_plan_prices
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_volume_tiers
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_customers
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_subscriptions
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_one_time_payments
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_charges
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_payment_methods
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_invoices
FROM anon,
  authenticated;
REVOKE ALL ON TABLE public.billing_usage_logs
FROM anon,
  authenticated;



-- Grant necessary permissions
GRANT SELECT ON TABLE public.billing_plans TO authenticated;
GRANT SELECT ON TABLE public.billing_plan_prices TO authenticated;
GRANT SELECT ON TABLE public.billing_volume_tiers TO authenticated;
GRANT SELECT ON TABLE public.billing_customers TO authenticated;
GRANT SELECT ON TABLE public.billing_subscriptions TO authenticated;
GRANT SELECT ON TABLE public.billing_one_time_payments TO authenticated;
GRANT SELECT ON TABLE public.billing_charges TO authenticated;
GRANT SELECT ON TABLE public.billing_payment_methods TO authenticated;
-- GRANT SELECT ON TABLE public.billing_credit_logs TO authenticated;
GRANT SELECT ON TABLE public.billing_invoices TO authenticated;
GRANT SELECT ON TABLE public.billing_usage_logs TO authenticated;

-- Enable Row Level Security (RLS) on the new tables
ALTER TABLE public.billing_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_plan_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_volume_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_subscriptions ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.billing_credit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_usage_logs ENABLE ROW LEVEL SECURITY;



-- -- Drop the existing customers and subscriptions tables if they exist
-- DROP TABLE IF EXISTS public.customers CASCADE;
-- DROP TABLE IF EXISTS public.subscriptions CASCADE;
DROP TABLE IF EXISTS public.subscriptions CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.prices CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;




-- Add RLS policies (these are basic examples and should be adjusted based on your specific requirements)
CREATE POLICY "Everyone can view plans" ON public.billing_plans FOR
SELECT USING (TRUE);

-- everyone can view billing_plan_prices
CREATE POLICY "Everyone can view billing_plan_prices" ON public.billing_plan_prices FOR
SELECT USING (TRUE);

-- everyone can view billing_volume_tiers
CREATE POLICY "Everyone can view billing_volume_tiers" ON public.billing_volume_tiers FOR
SELECT USING (TRUE);

-- workspace members can view their customer
CREATE POLICY "Workspace members can view their customer" ON public.billing_customers FOR
SELECT USING (
    public.is_workspace_member(
      workspace_id,
      (
        SELECT auth.uid()
      )
    )
  );


-- workspace members can view their subscriptions
CREATE POLICY "Workspace members can view their subscriptions" ON public.billing_subscriptions FOR
SELECT USING (
    public.is_workspace_member(
      public.get_customer_workspace_id(gateway_customer_id),
      (
        SELECT auth.uid()
      )
    )
  );

-- workspace members can view their invoices
CREATE POLICY "Workspace members can view their invoices" ON public.billing_invoices FOR
SELECT USING (
    public.is_workspace_member(
      public.get_customer_workspace_id(gateway_customer_id),
      (
        SELECT auth.uid()
      )
    )
  );

-- workspace members can view their usage logs
CREATE POLICY "Workspace members can view their usage logs" ON public.billing_usage_logs FOR
SELECT USING (
    public.is_workspace_member(
      public.get_customer_workspace_id(gateway_customer_id),
      (
        SELECT auth.uid()
      )
    )
  );

-- -- workspace members can view their credit logs
-- CREATE POLICY "Workspace members can view their credit logs" ON public.billing_credit_logs FOR
-- SELECT USING (
--     public.is_workspace_member(
--       public.get_customer_workspace_id(gateway_customer_id),
--       (
--         SELECT auth.uid()
--       )
--     )
--   );