import { getWorkspaceSlugById } from '@/data/user/workspaces';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { superAdminGetUserIdByEmail } from '@/supabase-clients/admin/user';
import { superAdminGetWorkspaceAdmins } from '@/supabase-clients/admin/workspaces';
import { supabaseAnonClient } from '@/supabase-clients/anon/supabaseAnonClient';
import { DBTable, DBTableInsertPayload } from '@/types';
import { toSiteURL } from '@/utils/helpers';
import 'server-only';
import Stripe from 'stripe';
import {
  CheckoutSessionData,
  CheckoutSessionOptions,
  CustomerData,
  CustomerPortalData,
  PaginatedResponse,
  PaginationOptions,
  PaymentGateway,
  PaymentGatewayError,
  PlanData
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

  db = {
    createCustomer: async (userData: Partial<DBTable<'billing_customers'>>, workspaceId: string): Promise<DBTable<'billing_customers'>> => {
      const { billing_email } = userData;
      if (!billing_email) {
        return this.util.handleStripeError(new Error('Email is required'));
      }
      const customer = await this.stripe.customers.create({
        email: billing_email,
        name: `Organization ${workspaceId}`,
        metadata: {
          organization_id: workspaceId,
        },
      });

      const { data, error } = await supabaseAdminClient
        .from('billing_customers')
        .insert({
          gateway_name: this.getName(),
          gateway_customer_id: customer.id,
          billing_email: billing_email,
          workspace_id: workspaceId,
        })
        .select('*')
        .single();

      if (error) throw error;

      return data;

    },

    getCustomerByCustomerId: async (customerId: string): Promise<DBTable<'billing_customers'>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_customers')
        .select('*')
        .eq('gateway_customer_id', customerId)
        .eq('gateway_name', this.getName())
        .single();

      if (error) throw error;

      return data;
    },

    getCustomerByWorkspaceId: async (workspaceId: string): Promise<DBTable<'billing_customers'>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_customers')
        .select('*')
        .eq('workspace_id', workspaceId)
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
        return this.util.handleStripeError(error);
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

    getSubscriptionsByCustomerId: async (customerId: string): Promise<Array<DBTable<'billing_subscriptions'>>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_subscriptions')
        .select('*')
        .eq('gateway_customer_id', customerId)
        .eq('gateway_name', this.getName())

      if (error) throw error;
      return data;
    },
    getSubscriptionsByWorkspaceId: async (workspaceId: string): Promise<Array<DBTable<'billing_subscriptions'>>> => {
      const customer = await this.db.getCustomerByWorkspaceId(workspaceId);
      if (!customer) {
        throw new Error('Customer not found');
      }
      const { data, error } = await supabaseAdminClient
        .from('billing_subscriptions')
        .select('*')
        .eq('gateway_customer_id', customer.gateway_customer_id)
        .eq('gateway_name', this.getName())

      if (error) throw error;
      return data;
    },

    getSubscription: async (subscriptionId: string): Promise<DBTable<'billing_subscriptions'>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_subscriptions')
        .select('*')
        .eq('gateway_subscription_id', subscriptionId)
        .single();

      if (error) {
        return this.util.handleStripeError(error);
      };

      return data;
    },

    listSubscriptions: async (customerId: string, options?: PaginationOptions): Promise<PaginatedResponse<DBTable<'billing_subscriptions'>>> => {
      const { data, error, count } = await supabaseAdminClient
        .from('billing_subscriptions')
        .select('*', { count: 'exact' })
        .eq('gateway_customer_id', customerId)
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

    getInvoice: async (invoiceId: string): Promise<DBTable<'billing_invoices'>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_invoices')
        .select('*')
        .eq('id', invoiceId)
        .single();

      if (error) throw error;

      return data;
    },

    listInvoicesByCustomerId: async (customerId: string, options?: PaginationOptions): Promise<PaginatedResponse<DBTable<'billing_invoices'>>> => {
      const { data, error, count } = await supabaseAdminClient
        .from('billing_invoices')
        .select('*', { count: 'exact' })
        .eq('gateway_customer_id', customerId)
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

    listInvoicesByWorkspaceId: async (workspaceId: string, options?: PaginationOptions): Promise<PaginatedResponse<DBTable<'billing_invoices'>>> => {
      const customer = await this.db.getCustomerByWorkspaceId(workspaceId);
      if (!customer) {
        throw new Error('Customer not found');
      }
      return this.db.listInvoicesByCustomerId(customer.gateway_customer_id, options);
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

    listPlans: async (): Promise<Array<PlanData>> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_plans')
        .select('*, billing_plan_prices(*)', { count: 'exact' })
        .eq('gateway_name', this.getName())


      if (error) throw error;
      return data;
    },
    getWorkspaceDatabaseCharges: async (workspaceId: string): Promise<DBTable<'billing_charges'>[]> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_charges')
        .select('*')
        .eq('workspace_id', workspaceId);
      if (error) throw error;
      return data;
    },
    getWorkspaceDatabaseOneTimePurchases: async (workspaceId: string): Promise<DBTable<'billing_one_time_payments'>[]> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_one_time_payments')
        .select('*')
        .eq('workspace_id', workspaceId);
      if (error) throw error;
      return data;
    },

    getWorkspaceDatabasePaymentMethods: async (workspaceId: string): Promise<DBTable<'billing_payment_methods'>[]> => {
      const { data, error } = await supabaseAdminClient
        .from('billing_payment_methods')
        .select('*')
        .eq('workspace_id', workspaceId);
      if (error) throw error;
      return data;
    },


  }

  util = {
    handleStripeError: (error: any) => {
      console.log('Stripe error', error);
      throw new PaymentGatewayError(error.message, error.code, this.getName());
    },
    isTestMode: () => {
      return process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY?.includes('pk_test') ?? false;
    },
    createCustomerForWorkspace: async (workspaceId: string): Promise<DBTable<'billing_customers'>> => {
      const workspaceAdmins = await superAdminGetWorkspaceAdmins(workspaceId);
      const orgAdminUserId = workspaceAdmins[0];
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

    createGatewayCustomer: async (userData: Partial<CustomerData>): Promise<CustomerData> => {
      const customer = await this.stripe.customers.create(userData);
      return {
        id: customer.id,
        email: customer.email!,
        metadata: customer.metadata,
      };
    },

    handleGatewayWebhook: async (body: any, signature: string): Promise<void> => {
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
          case 'product.created':
          case 'product.updated':
            await this.handleProductChange(event.data.object as Stripe.Product);
            break;
          case 'price.created':
          case 'price.updated':
            await this.handlePriceChange(event.data.object as Stripe.Price);
            break;
        }
      } catch (error) {
        this.util.handleStripeError(error);
      }
    },

  }

  private async handleSubscriptionChange(subscription: Stripe.Subscription) {
    if (!subscription.customer) {
      return this.util.handleStripeError(new Error('Subscription customer not found'));
    }
    const stripeCustomerId = typeof subscription.customer === 'string' ? subscription.customer : typeof subscription.customer === 'object' && 'id' in subscription.customer ? subscription.customer.id : null;
    if (!stripeCustomerId) {
      return this.util.handleStripeError(new Error('Subscription customer not found'));
    }

    const doesCustomerExist = await this.db.hasCustomer(stripeCustomerId)
    if (!doesCustomerExist) {

      // it is likely that a user with this billing email doesn't exist and this is the fast anon flow.
      // user clicks on pricing table on home page with no account and after payment, they are redirected to signup.
      // we need to create a user with this email and then create a customer for them.
      const billingEmail = typeof subscription.customer === 'string' ? subscription.customer : typeof subscription.customer === 'object' && 'email' in subscription.customer ? subscription.customer.email : null;
      if (!billingEmail) {
        return this.util.handleStripeError(new Error('Subscription customer email not found'));
      }
      const userId = await superAdminGetUserIdByEmail(billingEmail)
      if (!userId) {
        return this.util.handleStripeError(new Error('User not found'));
      }
      const { error: createUserError } = await supabaseAdminClient.auth.admin.createUser({
        email: billingEmail,
        email_confirm: true,
        id: userId,
      });

      if (createUserError) throw createUserError;

    }
    const { error } = await supabaseAdminClient
      .from('billing_subscriptions')
      .upsert({
        gateway_customer_id: stripeCustomerId,
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
      return this.util.handleStripeError(new Error('Invoice customer not found'));
    }
    const customerId = typeof invoice.customer === 'string' ? invoice.customer : typeof invoice.customer === 'object' && 'id' in invoice.customer ? invoice.customer.id : null;
    if (!customerId) {
      return this.util.handleStripeError(new Error('Invoice customer not found'));
    }
    const organizationId = await this.getOrganizationIdFromCustomer(customerId);
    if (!organizationId) {
      return this.util.handleStripeError(new Error('Organization not found'));
    }
    const dueDate = invoice.due_date;
    if (!dueDate) {
      return this.util.handleStripeError(new Error('Invoice due date not found'));
    }
    const paidDate = invoice.status_transitions.paid_at;
    const { error } = await supabaseAdminClient
      .from('billing_invoices')
      .upsert({
        gateway_customer_id: customerId,
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
      return this.util.handleStripeError(error);
    }
  }

  private async handleCustomerUpdate(customer: Stripe.Customer) {
    const email = customer.email
    if (!email) {
      return this.util.handleStripeError(new Error('Email is required'));
    }
    const { error } = await supabaseAdminClient
      .from('billing_customers')
      .update({
        billing_email: email,
      })
      .eq('gateway_customer_id', customer.id);

    if (error) throw error;
  }

  private async handleProductChange(product: Stripe.Product) {
    const { error } = await supabaseAdminClient
      .from('billing_plans')
      .upsert({
        gateway_plan_id: product.id,
        gateway_name: this.getName(),
        name: product.name,
        description: product.description,
        is_subscription: product.active,
        is_visible_in_ui: product.active,
        features: product.metadata.features,
      }, {
        onConflict: 'gateway_plan_id,gateway_name'
      });

    if (error) throw error;
  }

  private async handlePriceChange(price: Stripe.Price) {
    const { error } = await supabaseAdminClient
      .from('billing_plan_prices')
      .upsert({
        gateway_plan_id: price.product as string,
        gateway_name: this.getName(),
        gateway_price_id: price.id,
        currency: price.currency,
        amount: price.unit_amount ?? 0,
        recurring_interval: price.recurring?.interval ?? 'month',
        active: price.active,
      }, {
        onConflict: 'gateway_price_id'
      });

    if (error) throw error;
  }




  private async getOrganizationIdFromCustomer(stripeCustomerId: string): Promise<string | null> {
    const { data, error } = await supabaseAdminClient
      .from('billing_customers')
      .select('workspace_id')
      .eq('gateway_customer_id', stripeCustomerId)
      .eq('gateway_name', this.getName())
      .single();

    if (error) throw error;
    return data?.workspace_id || null;
  }

  anonScope = {
    listVisiblePlans: async (): Promise<PlanData[]> => {
      const { data: plans, error } = await supabaseAnonClient
        .from('billing_plans')
        .select('*, billing_plan_prices(*)')
        .eq('gateway_name', this.getName())
        .eq('is_visible_in_ui', true);
      if (error) throw error;

      return plans;
    },
  }


  userScope = {
    /**
     * Retrieves the database plan for a given workspace.
     *
     * @param workspaceId - The unique identifier of the workspace.
     * @returns A promise that resolves to the PlanData for the workspace.
     * @throws Error if the customer or plan is not found.
     */
    getWorkspaceDatabasePlan: async (workspaceId: string): Promise<PlanData> => {
      const databaseCustomer = await this.db.getCustomerByWorkspaceId(workspaceId);
      if (!databaseCustomer) {
        throw new Error('Customer not found');
      }
      const planId = databaseCustomer.gateway_plan_id;
      if (!planId) {
        throw new Error('Plan not found');
      }
      return this.db.getPlan(planId);
    },

    /**
     * Fetches the database subscription for a given workspace.
     *
     * @param workspaceId - The unique identifier of the workspace.
     * @returns A promise that resolves to the billing subscription data or null if not found.
     */
    getWorkspaceDatabaseSubscriptions: async (workspaceId: string): Promise<Array<DBTable<'billing_subscriptions'>>> => {
      return this.db.getSubscriptionsByWorkspaceId(workspaceId);
    },

    /**
     * Retrieves all one-time purchases for a given workspace.
     *
     * @param workspaceId - The unique identifier of the workspace.
     * @returns A promise that resolves to an array of billing payment data.
     */
    getWorkspaceDatabaseOneTimePurchases: async (workspaceId: string): Promise<DBTable<'billing_one_time_payments'>[]> => {
      return this.db.getWorkspaceDatabaseOneTimePurchases(workspaceId);
    },

    /**
     * Fetches all invoices for a given workspace.
     *
     * @param workspaceId - The unique identifier of the workspace.
     * @returns A promise that resolves to a paginated response of billing invoice data.
     */
    getWorkspaceDatabaseInvoices: async (workspaceId: string): Promise<PaginatedResponse<DBTable<'billing_invoices'>>> => {
      return this.db.listInvoicesByWorkspaceId(workspaceId);
    },

    getWorkspaceDatabaseCharges: async (workspaceId: string): Promise<DBTable<'billing_charges'>[]> => {
      return this.db.getWorkspaceDatabaseCharges(workspaceId);
    },

    /**
     * Retrieves all payment methods associated with a given workspace.
     *
     * @param workspaceId - The unique identifier of the workspace.
     * @returns A promise that resolves to an array of PaymentMethodData.
     */
    getWorkspaceDatabasePaymentMethods: async (workspaceId: string): Promise<DBTable<'billing_payment_methods'>[]> => {
      return this.db.getWorkspaceDatabasePaymentMethods(workspaceId);
    },

    /**
     * Fetches the customer data for a given workspace.
     *
     * @param workspaceId - The unique identifier of the workspace.
     * @returns A promise that resolves to the billing customer data.
     */
    getWorkspaceDatabaseCustomer: async (workspaceId: string): Promise<DBTable<'billing_customers'>> => {
      return this.db.getCustomerByWorkspaceId(workspaceId);
    },


    createGatewayCheckoutSession: async (workspaceId: string, planId: string, options?: CheckoutSessionOptions): Promise<CheckoutSessionData> => {
      let customer = await this.util.getCustomerByWorkspaceId(workspaceId);

      if (!customer) {
        customer = await this.util.createCustomerForWorkspace(workspaceId);
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

      const organizationSlug = await getWorkspaceSlugById(workspaceId);

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

    },

    createGatewayCustomerPortalSession: async (workspaceId: string, returnUrl: string): Promise<CustomerPortalData> => {
      const customer = await this.util.getCustomerByWorkspaceId(workspaceId);
      if (!customer) {
        throw new Error('Customer not found');
      }
      const session = await this.stripe.billingPortal.sessions.create({
        customer: customer.gateway_customer_id,
        return_url: returnUrl,
      });

      return {
        url: session.url,
      };

    },

  }

  superAdminScope = {
    syncCustomers: async (): Promise<void> => {
      try {
        const { data: customers, error: fetchError } = await supabaseAdminClient
          .from('billing_customers')
          .select('*')
          .eq('gateway_name', this.getName());

        if (fetchError) throw fetchError;
        const stripeCustomers = await this.stripe.customers.list({
          email: customers.map(customer => customer.billing_email).join(','),
        });
        const stripeCustomerMap = new Map<string, string>();

        stripeCustomers.data.forEach(customer => {
          if (customer.email) {
            stripeCustomerMap.set(customer.email, customer.id);
          }
        });

        for (const customer of customers) {
          if (stripeCustomerMap.has(customer.billing_email)) {
            const stripeCustomerId = stripeCustomerMap.get(customer.billing_email);
            if (stripeCustomerId) {
              await this.db.updateCustomer(stripeCustomerId, {
                gateway_customer_id: stripeCustomerMap.get(customer.billing_email),
              })
            }

          }
        }

        for (const stripeCustomer of stripeCustomers.data) {
          if (stripeCustomer.email && !customers.some(customer => customer.billing_email === stripeCustomer.email)) {
            await this.db.createCustomer({
              billing_email: stripeCustomer.email,
            }, stripeCustomer.metadata.organization_id);
          }
        }
      } catch (error) {
        this.util.handleStripeError(error);
      }
    },

    syncPlans: async (): Promise<void> => {

      const [stripePrices, products] = await Promise.all([
        this.stripe.prices.list({ active: true }),
        this.stripe.products.list({ active: true })
      ]);
      const productMap = new Map(products.data.map(product => [product.id, product]));

      const plansToUpsert = stripePrices.data.map(stripePlan => {
        const product = productMap.get(stripePlan.product as string);
        if (!product) throw new Error(`Product not found for plan ${stripePlan.id}`);

        return {
          gateway_plan_id: stripePlan.id,
          gateway_name: this.getName(),
          name: product.name,
          description: product.description,
          is_subscription: true,
          features: product.metadata.features ? JSON.parse(product.metadata.features) : null,
        };
      });

      console.log("plansToUpsert", plansToUpsert);
      console.log("stripePrices", stripePrices);

      const { error: upsertError } = await supabaseAdminClient
        .from('billing_plans')
        .upsert(plansToUpsert, { onConflict: 'gateway_plan_id,gateway_name' });
      if (upsertError) throw upsertError;

      const pricesToUpsert: DBTableInsertPayload<'billing_plan_prices'>[] = stripePrices.data.map(stripePlan => ({
        gateway_plan_id: stripePlan.id,
        currency: stripePlan.currency,
        amount: stripePlan.unit_amount ?? 0,
        recurring_interval: stripePlan.recurring?.interval ?? 'month',
        gateway_name: this.getName(),
        gateway_price_id: stripePlan.id,
        active: stripePlan.active,
      }));

      const { error: priceUpsertError } = await supabaseAdminClient
        .from('billing_plan_prices')
        .upsert(pricesToUpsert, { onConflict: 'gateway_price_id' });
      console.log("priceUpsertError", priceUpsertError);
      if (priceUpsertError) throw priceUpsertError;
    },

    togglePlanVisibility: async (planId: string, isVisible: boolean): Promise<void> => {
      await supabaseAdminClient
        .from('billing_plans')
        .update({ is_visible_in_ui: isVisible })
        .eq('gateway_plan_id', planId)
        .eq('gateway_name', this.getName());
    },

    listAllPlans: async (): Promise<PlanData[]> => {
      return this.db.listPlans();
    },

    getCurrentMRR: async (): Promise<number> => {
      return 0;
    },

    getRevenueByMonthSince: async (date: Date): Promise<{ month: Date, revenue: number }[]> => {
      return [];
    },
    getCurrentMonthlySubscriptions: async (): Promise<number> => {
      return 0;
    },
    getSubscriptionsByMonthSince: async (date: Date): Promise<{ month: Date, subscriptions: number }[]> => {
      return [];
    },
    getCurrentRevenueByPlan: async (): Promise<{ planId: string, revenue: number }[]> => {
      return [];
    },


  }
}
