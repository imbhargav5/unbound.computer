'use server';

import { createOrRetrieveCustomer } from '@/data/admin/stripe';
import { getOrganizationSlugByOrganizationId, getOrganizationTitle } from '@/data/user/organizations';
import { createSupabaseUserServerActionClient } from '@/supabase-clients/user/createSupabaseUserServerActionClient';
import { toSiteURL } from '@/utils/helpers';
import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import { stripe } from '@/utils/stripe';

export async function createCheckoutSessionAction({
  organizationId,
  priceId,
  isTrial = false,
}: {
  organizationId: string;
  priceId: string;
  isTrial?: boolean;
}) {
  'use server';
  const TRIAL_DAYS = 14;
  const user = await serverGetLoggedInUser();

  const organizationTitle = await getOrganizationTitle(organizationId);
  const organizationSlug = await getOrganizationSlugByOrganizationId(organizationId);

  const customer = await createOrRetrieveCustomer({
    organizationId: organizationId,
    organizationTitle: organizationTitle,
    email: user.email || '',
  });
  if (!customer) throw Error('Could not get customer');
  if (isTrial) {
    const stripeSession = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      billing_address_collection: 'required',
      customer,
      line_items: [
        {
          price: priceId,
          quantity: 1,
        },
      ],
      mode: 'subscription',
      allow_promotion_codes: true,
      subscription_data: {
        trial_period_days: TRIAL_DAYS,
        trial_settings: {
          end_behavior: {
            missing_payment_method: 'cancel',
          },
        },
        metadata: {},
      },
      success_url: toSiteURL(
        `/${organizationSlug}/settings/billing`,
      ),
      cancel_url: toSiteURL(`/${organizationSlug}/settings/billing`),
    });

    return stripeSession.id;
  }
  const stripeSession = await stripe.checkout.sessions.create({
    payment_method_types: ['card'],
    billing_address_collection: 'required',
    customer,
    line_items: [
      {
        price: priceId,
        quantity: 1,
      },
    ],
    mode: 'subscription',
    allow_promotion_codes: true,
    subscription_data: {
      trial_settings: {
        end_behavior: {
          missing_payment_method: 'cancel',
        },
      },
    },
    metadata: {},
    success_url: toSiteURL(
      `/${organizationSlug}/settings/billing`,
    ),
    cancel_url: toSiteURL(`/${organizationSlug}/settings/billing`),
  });

  return stripeSession.id;
}

export async function createCustomerPortalLinkAction(organizationId: string) {
  'use server';
  const user = await serverGetLoggedInUser();
  const supabaseClient = createSupabaseUserServerActionClient();
  const { data, error } = await supabaseClient
    .from('organizations')
    .select('id, title')
    .eq('id', organizationId)
    .single();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error('Organization not found');
  }

  const customer = await createOrRetrieveCustomer({
    organizationId: organizationId,
    organizationTitle: data.title,
    email: user.email || '',
  });

  const organizationSlug = await getOrganizationSlugByOrganizationId(organizationId);

  if (!customer) throw Error('Could not get customer');
  const { url } = await stripe.billingPortal.sessions.create({
    customer,
    return_url: toSiteURL(`/${organizationSlug}/settings/billing`),
  });

  return url;
}

export const manageSubsciptionStripe = async (organizationId: string) => {
  return await createCustomerPortalLinkAction(organizationId);
};

export const startTrialStripe = async (
  organizationId: string,
  priceId: string,
) => {
  return await createCheckoutSessionAction({
    organizationId,
    priceId,
    isTrial: true,
  });
};

export const getMRRStripe = async (startOfMonth: Date, endOfMonth: Date) => {
  let mrr = 0;
  const subscriptions = await getSubscriptionsListStripe(
    startOfMonth,
    endOfMonth,
  );

  subscriptions.data.forEach((sub) => {
    if (sub.status === 'active' || sub.status === 'trialing') {
      mrr +=
        ((sub.items.data[0].price.unit_amount ?? 0) *
          (sub.items.data[0].quantity ?? 0)) /
        100;
    }
  });
  return mrr;
};

export const getSubscriptionsListStripe = async (
  startOfMonth: Date,
  endOfMonth: Date,
) => {
  const subscriptions = await stripe.subscriptions.list({
    created: {
      gte: Math.floor(startOfMonth.getTime() / 1000),
      lt: Math.floor(endOfMonth.getTime() / 1000),
    },
    status: 'all',
  });
  return subscriptions;
};



interface MonthlyData {
  month: string;
  value: number;
}

const getLastSixMonths = (): Date[] => {
  const today = new Date();
  return Array.from({ length: 6 }, (_, i) => {
    const d = new Date(today.getFullYear(), today.getMonth() - i, 1);
    return d;
  }).reverse();
};

const formatMonth = (date: Date): string => {
  return date.toLocaleString('default', { month: 'long' });
};

export const getMonthlyChurn = async (): Promise<MonthlyData[]> => {
  const lastSixMonths = getLastSixMonths();
  const churnData: MonthlyData[] = [];

  for (const monthStart of lastSixMonths) {
    const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0);

    const canceledSubscriptions = await stripe.subscriptions.list({
      status: 'canceled',
      created: {
        gte: Math.floor(monthStart.getTime() / 1000),
        lt: Math.floor(monthEnd.getTime() / 1000),
      },
    });

    churnData.push({
      month: formatMonth(monthStart),
      value: canceledSubscriptions.data.length,
    });
  }

  return churnData;
};

export const getMonthlyMRR = async (): Promise<MonthlyData[]> => {
  const lastSixMonths = getLastSixMonths();
  const mrrData: MonthlyData[] = [];

  for (const monthStart of lastSixMonths) {
    const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0);

    const subscriptions = await stripe.subscriptions.list({
      created: {
        gte: Math.floor(monthStart.getTime() / 1000),
        lt: Math.floor(monthEnd.getTime() / 1000),
      },
      status: 'active',
    });

    let mrr = 0;
    subscriptions.data.forEach((sub) => {
      mrr += ((sub.items.data[0].price.unit_amount ?? 0) * (sub.items.data[0].quantity ?? 0)) / 100;
    });

    mrrData.push({
      month: formatMonth(monthStart),
      value: mrr,
    });
  }

  return mrrData;
};

export const getNewCustomers = async (): Promise<MonthlyData[]> => {
  const lastSixMonths = getLastSixMonths();
  const customerData: MonthlyData[] = [];

  for (const monthStart of lastSixMonths) {
    const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0);

    const customers = await stripe.customers.list({
      created: {
        gte: Math.floor(monthStart.getTime() / 1000),
        lt: Math.floor(monthEnd.getTime() / 1000),
      },
    });

    customerData.push({
      month: formatMonth(monthStart),
      value: customers.data.length,
    });
  }

  return customerData;
};
