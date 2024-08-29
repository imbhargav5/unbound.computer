-- Alter billing_invoices table to change id column type
ALTER TABLE public.billing_invoices
ALTER COLUMN id TYPE TEXT USING id::text;

-- Update the default value for the id column
ALTER TABLE public.billing_invoices
ALTER COLUMN id
SET DEFAULT gen_random_uuid()::text;