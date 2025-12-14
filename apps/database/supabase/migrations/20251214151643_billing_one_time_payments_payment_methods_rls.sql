-- Enable RLS on billing_one_time_payments and billing_payment_methods tables
-- Add RLS policies following the same pattern as billing_subscriptions table
-- Enable Row Level Security
ALTER TABLE public.billing_one_time_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_payment_methods ENABLE ROW LEVEL SECURITY;

-- Workspace members can view their one-time payments
CREATE POLICY "Workspace members can view their one-time payments" ON public.billing_one_time_payments FOR
SELECT USING (
    public.is_workspace_member(
      public.get_customer_workspace_id(gateway_customer_id),
      (
        SELECT auth.uid()
      )
    )
  );

-- Workspace members can view their payment methods
CREATE POLICY "Workspace members can view their payment methods" ON public.billing_payment_methods FOR
SELECT USING (
    public.is_workspace_member(
      public.get_customer_workspace_id(gateway_customer_id),
      (
        SELECT auth.uid()
      )
    )
  );

-- Rollback script (down migration)
-- DROP POLICY "Workspace members can view their one-time payments" ON public.billing_one_time_payments;
-- DROP POLICY "Workspace members can view their payment methods" ON public.billing_payment_methods;
-- ALTER TABLE public.billing_payment_methods DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.billing_one_time_payments DISABLE ROW LEVEL SECURITY;