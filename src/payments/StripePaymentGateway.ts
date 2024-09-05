'use server';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { DBTable } from '@/types';
import { toSiteURL } from '@/utils/helpers';
import Stripe from 'stripe';
import {
  CheckoutSessionData,
  CheckoutSessionOptions,
  CustomerData,
  CustomerPortalData,
  InvoiceData,
  PaginatedResponse,
  PaginationOptions,
  PaymentGateway,
  PaymentGatewayError,
  PlanData,
  SubscriptionData
} from './AbstractPaymentGateway';

export class StripePaymentGateway implements PaymentGateway {
  private stripe: Stripe;

  constructor() {
    if (!process.env.STRIPE_SECRET_KEY) {
      throw new Error('Stripe secret key is not configured');
    }
    this.stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
      apiVersion: '2023-10-16',
      appInfo: {
        name: 'Nextbase',
        version: '0.1.0',
      },
    });
  }

  getName(): string {
    return 'stripe';
  }

  private handleStripeError(error: any): never {
    throw new PaymentGatewayError(error.message, error.code, this.getName());
  }

  db = {
    createCustomer: async (userData: Partial<DBTable<'billing_customers'>>, organizationId: string): Promise<DBTable<'billing_customers'>> => {
      const { billing_email } = userData;
      if (!billing_email) {
        return this.handleStripeError(new Error('Email is required'));
      }
      try {
        const customer = await this.stripe.customers.create({
          email: billing_email,
          name: `Organization ${organizationId}`,
          metadata: {
            organization_id: organizationId,
          },
        });

        const { data, error } = await supabaseAdminClient
          .from('billing_customers')
          .insert({
            gateway_name: this.getName(),
            gateway_customer_id: customer.id,
            billing_email: billing_email,
            organization_id: organizationId,
          })
          .select('*')
          .single();

        if (error) throw error;

        return data;
      } catch (error) {
        this.handleStripeError(error);
      }
    },

    getCustomer: async (customerId: string): Promise<DBTable<'billing_customers'>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_customers')
        .select('*')
        .eq('gateway_customer_id', customerId)
        .eq('gateway_name', this.getName())
        .single();

      if (error) throw error;

      return data;
    },

    hasCustomer: async (customerId: string): Promise<boolean> => {
      const { count, error } = await supabaseAdminClient
        .from('billing_customers')
        .select('*', { count: 'exact', head: true })
        .eq('gateway_customer_id', customerId)
        .eq('gateway_name', this.getName());

      if (error) throw error;

      return (count ?? 0) > 0;
    },

    updateCustomer: async (customerId: string, updateData: Partial<DBTable<'billing_customers'>>): Promise<DBTable<'billing_customers'>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_customers')
        .update(updateData)
        .eq('gateway_customer_id', customerId)
        .eq('gateway_name', this.getName())
        .select('*')
        .single();

      if (error) {
        return this.handleStripeError(error);
      }

      return data;
    },

    deleteCustomer: async (customerId: string): Promise<void> => {
      const { error } = await supabaseAdminClient
        .from('billing_customers')
        .delete()
        .eq('gateway_customer_id', customerId);

      if (error) throw error;
    },

    listCustomers: async (options?: PaginationOptions): Promise<PaginatedResponse<DBTable<'billing_customers'>>> => {
      const { data, error, count } = await supabaseAdminClient
        .from('billing_customers')
        .select('*', { count: 'exact' })
        .eq('gateway_name', this.getName())
        .range(
          options?.startingAfter ? parseInt(options.startingAfter) : 0,
          options?.limit ? parseInt(options.startingAfter || '0') + options.limit - 1 : 9999
        );

      if (error) throw error;

      return {
        data,
        hasMore: count! > (options?.limit || 0) + (parseInt(options?.startingAfter || '0')),
        totalCount: count ?? 0,
      };
    },

    getSubscription: async (subscriptionId: string): Promise<SubscriptionData> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_subscriptions')
        .select('*')
        .eq('gateway_subscription_id', subscriptionId)
        .single();

      if (error) {
        return this.handleStripeError(error);
      };

      return {
        id: data.gateway_subscription_id,
        customerId: data.customer_id,
        planId: data.gateway_plan_id,
        status: data.status,
        currentPeriodStart: new Date(data.current_period_start),
        currentPeriodEnd: new Date(data.current_period_end),
        cancelAtPeriodEnd: data.cancel_at_period_end,
      };
    },

    listSubscriptions: async (customerId: string, options?: PaginationOptions): Promise<PaginatedResponse<SubscriptionData>> => {
      const { data, error, count } = await supabaseAdminClient
        .from('billing_subscriptions')
        .select('*', { count: 'exact' })
        .eq('customer_id', customerId)
        .eq('gateway_name', this.getName())
        .range(
          options?.startingAfter ? parseInt(options.startingAfter) : 0,
          options?.limit ? parseInt(options.startingAfter || '0') + options.limit - 1 : 9999
        );

      if (error) throw error;

      return {
        data: data.map(subscription => ({
          id: subscription.gateway_subscription_id,
          customerId: subscription.customer_id,
          planId: subscription.gateway_plan_id,
          status: subscription.status,
          currentPeriodStart: new Date(subscription.current_period_start),
          currentPeriodEnd: new Date(subscription.current_period_end),
          cancelAtPeriodEnd: subscription.cancel_at_period_end,
        })),
        hasMore: count! > (options?.limit || 0) + (parseInt(options?.startingAfter || '0')),
        totalCount: count ?? 0,
      };
    },

    getInvoice: async (invoiceId: string): Promise<InvoiceData> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_invoices')
        .select('*')
        .eq('id', invoiceId)
        .single();

      if (error) throw error;

      return data;
    },

    listInvoices: async (customerId: string, options?: PaginationOptions): Promise<PaginatedResponse<InvoiceData>> => {
      const { data, error, count } = await supabaseAdminClient
        .from('billing_invoices')
        .select('*', { count: 'exact' })
        .eq('organization_id', customerId)
        .range(
          options?.startingAfter ? parseInt(options.startingAfter) : 0,
          options?.limit ? parseInt(options.startingAfter || '0') + options.limit - 1 : 9999
        );

      if (error) throw error;

      return {
        data,
        hasMore: count! > (options?.limit || 0) + (parseInt(options?.startingAfter || '0')),
        totalCount: count ?? 0,
      };
    },

    getPlan: async (planId: string): Promise<PlanData> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_plans')
        .select('*, billing_plan_prices(*)')
        .eq('gateway_plan_id', planId)
        .eq('gateway_name', this.getName())
        .single();

      if (error) throw error;
      return data;
    },

    listPlans: async (options?: PaginationOptions): Promise<PaginatedResponse<PlanData>> => {
      const { data, error, count } = await supabaseAdminClient
        .from('billing_plans')
        .select('*, billing_plan_prices(*)', { count: 'exact' })
        .eq('gateway_name', this.getName())
        .range(
          options?.startingAfter ? parseInt(options.startingAfter) : 0,
          options?.limit ? parseInt(options.startingAfter || '0') + options.limit - 1 : 9999
        );

      if (error) throw error;

      return {
        data,
        hasMore: count! > (options?.limit || 0) + (parseInt(options?.startingAfter || '0')),
        totalCount: count ?? 0,
      };
    },
  }

  util = {
    createCustomerForWorkspace: async (workspaceId: string): Promise<DBTable<'billing_customers'>> => {
      const workspaceAdmins = await getWorkspaceAdmins(workspaceId);
      if (!workspaceAdmins) throw new Error('Workspace admins not found');
      const orgAdminUserId = orgAdmins[0].user_profiles.id;
      if (!orgAdminUserId) throw new Error('Organization admin email not found');
      const { data: orgAdminUser, error: orgAdminUserError } = await supabaseAdminClient.auth.admin.getUserById(orgAdminUserId);
      if (orgAdminUserError) throw orgAdminUserError;
      if (!orgAdminUser) throw new Error('Organization admin user not found');
      const maybeEmail = orgAdminUser.user.email;
      if (!maybeEmail) throw new Error('Organization admin email not found');
      return this.db.createCustomer({
        billing_email: maybeEmail,
      }, workspaceId);
    },

    getCustomerByWorkspaceId: async (workspaceId: string): Promise<DBTable<'billing_customers'> | null> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_customers')
        .select('*')
        .eq('workspace_id', workspaceId)
        .eq('gateway_name', this.getName())
        .single();

      if (error) {
        if (error.code === 'PGRST116') {
          return null;
        }
        throw error;
      }

      return data;
    },

    supportsFeature: (featureName: string): boolean => {
      const supportedFeatures = [
        'subscriptions',
        'invoices',
        'customer_portal',
        'webhooks',
        'multiple_payment_methods',
      ];
      return supportedFeatures.includes(featureName);
    }
  }

  gateway = {
    createCustomer: async (userData: Partial<CustomerData>): Promise<CustomerData> => {
      const customer = await this.stripe.customers.create(userData);
      return {
        id: customer.id,
        email: customer.email!,
        metadata: customer.metadata,
      };
    },

    handleWebhook: async (body: any, signature: string): Promise<void> => {
      try {
        const event = this.stripe.webhooks.constructEvent(
          body,
          signature,
          process.env.STRIPE_WEBHOOK_SECRET!
        );

        switch (event.type) {
          case 'customer.subscription.created':
          case 'customer.subscription.updated':
          case 'customer.subscription.deleted':
            await this.handleSubscriptionChange(event.data.object as Stripe.Subscription);
            break;
          case 'invoice.paid':
          case 'invoice.payment_failed':
            await this.handleInvoiceChange(event.data.object as Stripe.Invoice);
            break;
          case 'customer.updated':
            await this.handleCustomerUpdate(event.data.object as Stripe.Customer);
            break;
        }
      } catch (error) {
        this.handleStripeError(error);
      }
    },

    createCheckoutSession: async (organizationId: string, planId: string, options?: CheckoutSessionOptions): Promise<CheckoutSessionData> => {
      try {
        let customer = await this.util.getCustomerByOrganizationId(organizationId);

        if (!customer) {
          customer = await this.util.createCustomerForOrganization(organizationId);
        }

        const { isTrial } = options ?? {};
        const plan = await this.db.getPlan(planId);
        if (!plan) {
          throw new Error('Plan not found');
        }

        const allowsFreeTrial = (plan.free_trial_days ?? 0) > 0;

        if (isTrial && !allowsFreeTrial) {
          throw new Error('This plan does not offer a free trial');
        }

        const organizationSlug = await getOrganizationSlugByOrganizationId(organizationId);

        let sessionConfig: Stripe.Checkout.SessionCreateParams = {
          customer: customer.gateway_customer_id,
          payment_method_types: ['card'],
          billing_address_collection: 'required',
          line_items: [{ price: planId, quantity: 1 }],
          mode: 'subscription',
          allow_promotion_codes: true,
          success_url: toSiteURL(`/${organizationSlug}/settings/billing`),
          cancel_url: toSiteURL(`/${organizationSlug}/settings/billing`),
        };

        if (isTrial && allowsFreeTrial) {
          sessionConfig.subscription_data = {
            trial_period_days: plan.free_trial_days ?? 14,
            trial_settings: {
              end_behavior: {
                missing_payment_method: 'cancel',
              },
            },
            metadata: {},
          };
        } else {
          sessionConfig.subscription_data = {
            trial_settings: {
              end_behavior: {
                missing_payment_method: 'cancel',
              },
            },
          };
        }

        const session = await this.stripe.checkout.sessions.create(sessionConfig);

        return {
          id: session.id,
          url: session.url!,
        };
      } catch (error) {
        this.handleStripeError(error);
      }
    },

    createCustomerPortalSession: async (gatewayCustomerId: string, returnUrl: string): Promise<CustomerPortalData> => {
      try {
        const session = await this.stripe.billingPortal.sessions.create({
          customer: gatewayCustomerId,
          return_url: returnUrl,
        });

        return {
          url: session.url,
        };
      } catch (error) {
        this.handleStripeError(error);
      }
    },

    syncPlans: async (): Promise<void> => {
      try {
        const stripePlans = await this.stripe.plans.list({ active: true });
        const { data: existingPlans, error: fetchError } = await supabaseAdminClient
          .from('billing_plans')
          .select('gateway_plan_id')
          .eq('gateway_name', this.getName());

        if (fetchError) throw fetchError;

        const existingPlanMap = new Map(existingPlans.map(plan => [plan.gateway_plan_id, true]));

        for (const stripePlan of stripePlans.data) {
          const product = await this.stripe.products.retrieve(stripePlan.product as string);

          const planData = {
            gateway_plan_id: stripePlan.id,
            gateway_name: this.getName(),
            name: product.name,
            description: product.description,
            is_subscription: true,
            features: product.metadata.features ? JSON.parse(product.metadata.features) : null,
          };

          if (existingPlanMap.has(stripePlan.id)) {
            await supabaseAdminClient
              .from('billing_plans')
              .update(planData)
              .eq('gateway_plan_id', stripePlan.id)
              .eq('gateway_name', this.getName());
          } else {
            await supabaseAdminClient
              .from('billing_plans')
              .insert(planData);
          }

          await supabaseAdminClient
            .from('billing_plan_prices')
            .upsert({
              plan_id: stripePlan.id,
              currency: stripePlan.currency,
              amount: stripePlan.amount!,
              recurring_interval: stripePlan.interval,
            }, {
              onConflict: 'plan_id,currency'
            });
        }
      } catch (error) {
        this.handleStripeError(error);
      }
    },
  }

  private async handleSubscriptionChange(subscription: Stripe.Subscription) {
    if (!subscription.customer) {
      return this.handleStripeError(new Error('Subscription customer not found'));
    }
    const stripeCustomerId = typeof subscription.customer === 'string' ? subscription.customer : typeof subscription.customer === 'object' && 'id' in subscription.customer ? subscription.customer.id : null;
    if (!stripeCustomerId) {
      return this.handleStripeError(new Error('Subscription customer not found'));
    }

    const doesCustomerExist = await this.db.hasCustomer(stripeCustomerId)
    if (!doesCustomerExist) {

      // it is likely that a user with this billing email doesn't exist and this is the fast anon flow.
      // user clicks on pricing table on home page with no account and after payment, they are redirected to signup.
      // we need to create a user with this email and then create a customer for them.
      const billingEmail = typeof subscription.customer === 'string' ? subscription.customer : typeof subscription.customer === 'object' && 'email' in subscription.customer ? subscription.customer.email : null;
      if (!billingEmail) {
        return this.handleStripeError(new Error('Subscription customer email not found'));
      }
      const createUserResponse = await getUserByEmail(billingEmail)
      if (createUserResponse.status == 'error') {
        return this.handleStripeError(createUserResponse.message);
      }
      const user = createUserResponse.data;
    }
    const { error } = await supabaseAdminClient
      .from('billing_subscriptions')
      .upsert({
        customer_id: stripeCustomerId,
        gateway_name: this.getName(),
        gateway_subscription_id: subscription.id,
        gateway_plan_id: subscription.items.data[0].price.id,
        status: subscription.status,
        current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
        current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
        currency: subscription.currency,
        is_trial: subscription.trial_end !== null,
        cancel_at_period_end: subscription.cancel_at_period_end,
        quantity: subscription.items.data[0].quantity,
      });

    if (error) throw error;
  }

  private async handleInvoiceChange(invoice: Stripe.Invoice) {
    if (!invoice.customer) {
      return this.handleStripeError(new Error('Invoice customer not found'));
    }
    const customerId = typeof invoice.customer === 'string' ? invoice.customer : typeof invoice.customer === 'object' && 'id' in invoice.customer ? invoice.customer.id : null;
    if (!customerId) {
      return this.handleStripeError(new Error('Invoice customer not found'));
    }
    const organizationId = await this.getOrganizationIdFromCustomer(customerId);
    if (!organizationId) {
      return this.handleStripeError(new Error('Organization not found'));
    }
    const dueDate = invoice.due_date;
    if (!dueDate) {
      return this.handleStripeError(new Error('Invoice due date not found'));
    }
    const paidDate = invoice.status_transitions.paid_at;
    const { error } = await supabaseAdminClient
      .from('billing_invoices')
      .upsert({
        amount: invoice.total,
        currency: invoice.currency,
        status: invoice.status ?? 'unknown',
        due_date: new Date(dueDate * 1000).toISOString(),
        paid_date: paidDate ? new Date(paidDate * 1000).toISOString() : null,
        id: invoice.id,
        organization_id: organizationId,
        hosted_invoice_url: invoice.hosted_invoice_url,
      }, {
        onConflict: 'id'
      });

    if (error) {
      return this.handleStripeError(error);
    }
  }

  private async handleCustomerUpdate(customer: Stripe.Customer) {
    const email = customer.email
    if (!email) {
      return this.handleStripeError(new Error('Email is required'));
    }
    const { error } = await supabaseAdminClient
      .from('billing_customers')
      .update({
        billing_email: email,
      })
      .eq('gateway_customer_id', customer.id);

    if (error) throw error;
  }

  private async getOrganizationIdFromCustomer(stripeCustomerId: string): Promise<string | null> {
    const { data, error } = await supabaseAdminClient
      .from('billing_customers')
      .select('organization_id')
      .eq('gateway_customer_id', stripeCustomerId)
      .eq('gateway_name', this.getName())
      .single();

    if (error) throw error;
    return data?.organization_id || null;
  }
}
function getOrganizationAdmins(organizationId: string) {
  throw new Error('Function not implemented.');
}

