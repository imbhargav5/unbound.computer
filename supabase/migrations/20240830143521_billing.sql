-- Plans table
CREATE TABLE IF NOT EXISTS public.billing_plans (
  gateway_plan_id VARCHAR PRIMARY KEY,
  gateway_name VARCHAR NOT NULL,
  name VARCHAR NOT NULL,
  description TEXT,
  is_subscription BOOLEAN NOT NULL,
  free_trial_days INT,
  features JSONB,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE(gateway_name, gateway_plan_id)
);

-- Plan Prices table
CREATE TABLE IF NOT EXISTS public.billing_plan_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id VARCHAR NOT NULL REFERENCES public.billing_plans(gateway_plan_id),
  currency VARCHAR NOT NULL,
  amount DECIMAL NOT NULL,
  recurring_interval VARCHAR NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  tier VARCHAR
);

-- Volume Tiers table
CREATE TABLE IF NOT EXISTS public.billing_volume_tiers (
  "id" "uuid" PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  plan_price_id UUID NOT NULL REFERENCES public.billing_plan_prices(id),
  min_quantity INT NOT NULL,
  max_quantity INT,
  unit_price DECIMAL NOT NULL
);

-- Customers table
CREATE TABLE IF NOT EXISTS public.billing_customers (
  gateway_customer_id VARCHAR PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id),
  gateway_name VARCHAR NOT NULL,
  current_plan_id VARCHAR REFERENCES public.billing_plans(gateway_plan_id),
  default_currency VARCHAR,
  billing_email VARCHAR NOT NULL,
  metadata JSONB DEFAULT '{}',
  UNIQUE (workspace_id, gateway_name)
);

-- Subscriptions table
CREATE TABLE IF NOT EXISTS public.billing_subscriptions (
  id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_customer_id VARCHAR NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  gateway_name VARCHAR NOT NULL,
  gateway_subscription_id VARCHAR NOT NULL,
  gateway_plan_id VARCHAR NOT NULL,
  STATUS public.subscription_status NOT NULL,
  current_period_start DATE NOT NULL,
  current_period_end DATE NOT NULL,
  currency VARCHAR NOT NULL,
  is_trial BOOLEAN NOT NULL,
  trial_ends_at DATE,
  cancel_at_period_end BOOLEAN NOT NULL,
  quantity INT,
  UNIQUE(gateway_name, gateway_subscription_id)
);

-- Payments table
CREATE TABLE IF NOT EXISTS public.billing_payments (
  gateway_payment_id VARCHAR PRIMARY KEY,
  gateway_name VARCHAR NOT NULL,
  gateway_customer_id VARCHAR NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  amount DECIMAL NOT NULL,
  currency VARCHAR NOT NULL,
  STATUS VARCHAR NOT NULL,
  payment_date TIMESTAMP WITH TIME ZONE NOT NULL,
  plan_id VARCHAR REFERENCES public.billing_plans(gateway_plan_id)
);

-- Credit Logs table
CREATE TABLE IF NOT EXISTS public.billing_credit_logs (
  id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_customer_id VARCHAR NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  amount INT NOT NULL,
  balance_after INT NOT NULL,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Invoices table
CREATE TABLE IF NOT EXISTS public.billing_invoices (
  id TEXT PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"()::text NOT NULL,
  gateway_customer_id VARCHAR NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  amount DECIMAL NOT NULL,
  currency VARCHAR NOT NULL,
  STATUS VARCHAR NOT NULL,
  due_date DATE NOT NULL,
  paid_date DATE,
  hosted_invoice_url VARCHAR
);

-- Usage Logs table
CREATE TABLE IF NOT EXISTS public.billing_usage_logs (
  id UUID PRIMARY KEY DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
  gateway_customer_id VARCHAR NOT NULL REFERENCES public.billing_customers(gateway_customer_id),
  feature VARCHAR NOT NULL,
  usage_amount INT NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- functions
CREATE OR REPLACE FUNCTION "public"."get_customer_workspace_id" (customer_id_arg VARCHAR) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE workspace_id UUID;
BEGIN
SELECT c."workspace_id" INTO workspace_id
FROM "public"."billing_customers" c
WHERE c."gateway_customer_id" = customer_id_arg;
RETURN workspace_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_customer_workspace_id(VARCHAR)
FROM anon;
REVOKE ALL ON FUNCTION public.get_customer_workspace_id(VARCHAR)
FROM authenticated;

-- Add indexes for better query performance
CREATE INDEX idx_billing_plan_prices_plan_id ON public.billing_plan_prices(plan_id);
CREATE INDEX idx_billing_volume_tiers_plan_price_id ON public.billing_volume_tiers(plan_price_id);
CREATE INDEX idx_billing_customers_workspace_id_gateway_name ON public.billing_customers(workspace_id, gateway_name);
CREATE INDEX idx_billing_subscriptions_customer_id_gateway_name ON public.billing_subscriptions(gateway_customer_id, gateway_name);
CREATE INDEX idx_billing_payments_gateway_customer_id_gateway_name ON public.billing_payments(gateway_customer_id, gateway_name);
CREATE INDEX idx_billing_payments_gateway_customer_id_gateway_name_status ON public.billing_payments(gateway_customer_id, gateway_name, STATUS);
CREATE INDEX idx_billing_credit_logs_gateway_customer_id ON public.billing_credit_logs(gateway_customer_id);
CREATE INDEX idx_billing_invoices_gateway_customer_id ON public.billing_invoices(gateway_customer_id);
CREATE INDEX idx_billing_usage_logs_gateway_customer_id ON public.billing_usage_logs(gateway_customer_id);

-- Grant necessary permissions
GRANT ALL ON TABLE public.billing_plans TO authenticated;
GRANT ALL ON TABLE public.billing_plan_prices TO authenticated;
GRANT ALL ON TABLE public.billing_volume_tiers TO authenticated;
GRANT ALL ON TABLE public.billing_customers TO authenticated;
GRANT ALL ON TABLE public.billing_subscriptions TO authenticated;
GRANT ALL ON TABLE public.billing_payments TO authenticated;
GRANT ALL ON TABLE public.billing_credit_logs TO authenticated;
GRANT ALL ON TABLE public.billing_invoices TO authenticated;
GRANT ALL ON TABLE public.billing_usage_logs TO authenticated;

-- Enable Row Level Security (RLS) on the new tables
ALTER TABLE public.billing_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_plan_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_volume_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_credit_logs ENABLE ROW LEVEL SECURITY;
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

-- workspace members can view their payments
CREATE POLICY "Workspace members can view their payments" ON public.billing_payments FOR
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

-- workspace members can view their credit logs
CREATE POLICY "Workspace members can view their credit logs" ON public.billing_credit_logs FOR
SELECT USING (
    public.is_workspace_member(
      public.get_customer_workspace_id(gateway_customer_id),
      (
        SELECT auth.uid()
      )
    )
  );