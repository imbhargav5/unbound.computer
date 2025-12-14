-- =============================================================================
-- Fix RLS Policies for marketing_feedback_boards
-- =============================================================================
-- The original "Only admins can manage boards" policy used FOR ALL which
-- includes SELECT operations. This caused 401 errors for anonymous users
-- because the admin check subquery references user_roles table which has
-- restrictive RLS policies.
--
-- This migration splits the admin policy into separate INSERT, UPDATE, DELETE
-- policies so that the public SELECT policy can work independently.
-- =============================================================================

-- Drop the existing "Only admins can manage boards" policy
DROP POLICY IF EXISTS "Only admins can manage boards" ON public.marketing_feedback_boards;

-- Recreate as separate policies for INSERT, UPDATE, DELETE only (not SELECT)
CREATE POLICY "Only admins can insert boards" ON public.marketing_feedback_boards
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'admin'
  )
);

CREATE POLICY "Only admins can update boards" ON public.marketing_feedback_boards
FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'admin'
  )
);

CREATE POLICY "Only admins can delete boards" ON public.marketing_feedback_boards
FOR DELETE
USING (
  EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'admin'
  )
);
