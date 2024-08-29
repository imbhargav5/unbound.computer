import Stripe from 'stripe';

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  // https://github.com/stripe/stripe-node#configuration
  apiVersion: '2023-10-16',
  // Register this as an official Stripe plugin.
  // https://stripe.com/docs/building-plugins#setappinfo
  appInfo: {
    name: 'Nextbase',
    version: '0.1.0',
  },
});

export function validateStripeKeys({
  stripeSecretKey,
  stripePublishableKey,
  stripeWebhookSecret,
}: {
  stripeSecretKey: string;
  stripePublishableKey: string;
  stripeWebhookSecret: string;
}): boolean {
  if (!stripeSecretKey || !stripePublishableKey || !stripeWebhookSecret) {
    return false;
  }
  // check if the keys are valid. stripe secret key should start with "sk_test_" or "sk_live_"
  // and stripe publishable key should start with "pk_test_" or "pk_live_"
  const secretKeyValid =
    stripeSecretKey.startsWith('sk_test_') ||
    stripeSecretKey.startsWith('sk_live_');
  const publishableKeyValid =
    stripePublishableKey.startsWith('pk_test_') ||
    stripePublishableKey.startsWith('pk_live_');
  if (!secretKeyValid || !publishableKeyValid) {
    return false;
  }
  return Boolean(
    stripeSecretKey && stripePublishableKey && stripeWebhookSecret,
  );
}
