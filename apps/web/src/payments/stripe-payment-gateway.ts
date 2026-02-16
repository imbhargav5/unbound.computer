import { type Dictionary, groupBy } from "lodash";
import Stripe from "stripe";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { superAdminGetUserIdByEmail } from "@/supabase-clients/admin/user";
import { supabaseAnonClient } from "@/supabase-clients/anon/supabase-anon-client";
import type { DBTable, DBTableInsertPayload } from "@/types";
import { convertAmountToUSD } from "@/utils/currency";
import { toSiteURL } from "@/utils/helpers";
import {
  type CheckoutSessionData,
  type CheckoutSessionOptions,
  type CustomerData,
  type CustomerPortalData,
  type GatewaySubscriptionData,
  type InvoiceData,
  type OneTimePaymentData,
  type PaginatedResponse,
  type PaginationOptions,
  type PaymentGateway,
  PaymentGatewayError,
  type ProductAndPrice,
  type ProductData,
  type SubscriptionData,
} from "./abstract-payment-gateway";

type StripeCustomerLinkInput = {
  gatewayCustomerId: string;
  billingEmail: string;
  linkedUserId: string | null;
};

export class StripeWebhookProcessingError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
    public readonly eventId?: string,
    public readonly eventType?: string,
    public readonly cause?: unknown
  ) {
    super(message);
    this.name = "StripeWebhookProcessingError";
  }
}

export class StripePaymentGateway implements PaymentGateway {
  private stripe: Stripe;

  constructor() {
    if (!process.env.STRIPE_SECRET_KEY) {
      throw new Error("Stripe secret key is not configured");
    }
    this.stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
      apiVersion: "2025-08-27.basil",
      appInfo: {
        name: "Outbound",
        version: "0.1.0",
      },
    });
  }

  getName(): string {
    return "stripe";
  }

  db = {
    createCustomer: async (
      userData: Partial<DBTable<"billing_customers">>,
      userId: string
    ): Promise<DBTable<"billing_customers">> => {
      const { billing_email } = userData;
      try {
        if (!billing_email) {
          return this.util.handleStripeError(new Error("Email is required"));
        }
        const customer = await this.stripe.customers.create({
          email: billing_email,
          name: `User ${userId}`,
          metadata: {
            user_id: userId,
          },
        });

        const { data, error } = await supabaseAdminClient
          .from("billing_customers")
          .insert({
            gateway_name: this.getName(),
            gateway_customer_id: customer.id,
            billing_email,
            user_id: userId,
          })
          .select("*")
          .single();

        if (error) throw error;

        return data;
      } catch (error) {
        return this.util.handleStripeError(error);
      }
    },

    getCustomerByCustomerId: async (
      customerId: string
    ): Promise<DBTable<"billing_customers">> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_customers")
        .select("*")
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName())
        .single();

      if (error) throw error;

      return data;
    },

    getCustomerByUserId: async (
      userId: string
    ): Promise<DBTable<"billing_customers">> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_customers")
        .select("*")
        .eq("user_id", userId)
        .eq("gateway_name", this.getName())
        .single();

      if (error) throw error;

      return data;
    },

    hasCustomer: async (customerId: string): Promise<boolean> => {
      const { count, error } = await supabaseAdminClient
        .from("billing_customers")
        .select("*", { count: "exact", head: true })
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName());

      if (error) throw error;

      return (count ?? 0) > 0;
    },

    updateCustomer: async (
      customerId: string,
      updateData: Partial<DBTable<"billing_customers">>
    ): Promise<DBTable<"billing_customers">> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_customers")
        .update(updateData)
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName())
        .select("*")
        .single();

      if (error) {
        return this.util.handleStripeError(error);
      }

      return data;
    },

    deleteCustomer: async (customerId: string): Promise<void> => {
      const { error } = await supabaseAdminClient
        .from("billing_customers")
        .delete()
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName());

      if (error) throw error;
    },

    listCustomers: async (
      options?: PaginationOptions
    ): Promise<PaginatedResponse<DBTable<"billing_customers">>> => {
      const { data, error, count } = await supabaseAdminClient
        .from("billing_customers")
        .select("*", { count: "exact" })
        .eq("gateway_name", this.getName())
        .range(
          options?.startingAfter ? Number.parseInt(options.startingAfter) : 0,
          options?.limit
            ? Number.parseInt(options.startingAfter || "0") + options.limit - 1
            : 9999
        );

      if (error) throw error;
      const total = count ?? 0;
      return {
        data,
        hasMore:
          total >
          (options?.limit || 0) +
            Number.parseInt(options?.startingAfter || "0"),
        totalCount: total,
      };
    },

    getSubscriptionsByCustomerId: async (
      customerId: string
    ): Promise<SubscriptionData[]> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_subscriptions")
        .select("*, billing_products(*), billing_prices(*)")
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName());

      if (error) throw error;
      return data;
    },
    getSubscriptionsByUserId: async (
      userId: string
    ): Promise<SubscriptionData[]> => {
      let customer: DBTable<"billing_customers"> | undefined;
      try {
        customer = await this.db.getCustomerByUserId(userId);
      } catch (error) {
        console.warn("Customer not found");
        return [];
      }
      if (!customer) {
        return [];
      }
      const { data, error } = await supabaseAdminClient
        .from("billing_subscriptions")
        .select("*, billing_products(*), billing_prices(*)")
        .eq("gateway_customer_id", customer.gateway_customer_id)
        .eq("gateway_name", this.getName());

      if (error) throw error;
      return data;
    },

    getSubscription: async (
      subscriptionId: string
    ): Promise<SubscriptionData> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_subscriptions")
        .select("*, billing_products(*), billing_prices(*)")
        .eq("gateway_subscription_id", subscriptionId)
        .eq("gateway_name", this.getName())
        .single();

      if (error) {
        return this.util.handleStripeError(error);
      }

      return data;
    },

    listSubscriptions: async (
      customerId: string,
      options?: PaginationOptions
    ): Promise<PaginatedResponse<SubscriptionData>> => {
      const { data, error, count } = await supabaseAdminClient
        .from("billing_subscriptions")
        .select("*, billing_products(*), billing_prices(*)", { count: "exact" })
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName())
        .range(
          options?.startingAfter ? Number.parseInt(options.startingAfter) : 0,
          options?.limit
            ? Number.parseInt(options.startingAfter || "0") + options.limit - 1
            : 9999
        );

      if (error) throw error;
      const total = count ?? 0;
      return {
        data,
        hasMore:
          total >
          (options?.limit || 0) +
            Number.parseInt(options?.startingAfter || "0"),
        totalCount: total,
      };
    },

    getInvoice: async (invoiceId: string): Promise<InvoiceData> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_invoices")
        .select("*, billing_products(*), billing_prices(*)")
        .eq("gateway_invoice_id", invoiceId)
        .eq("gateway_name", this.getName())
        .single();

      if (error) throw error;

      return data;
    },

    listInvoicesByCustomerId: async (
      customerId: string,
      options?: PaginationOptions
    ): Promise<PaginatedResponse<InvoiceData>> => {
      const { data, error, count } = await supabaseAdminClient
        .from("billing_invoices")
        .select("*, billing_products(*), billing_prices(*)", { count: "exact" })
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName())
        .range(
          options?.startingAfter ? Number.parseInt(options.startingAfter) : 0,
          options?.limit
            ? Number.parseInt(options.startingAfter || "0") + options.limit - 1
            : 9999
        );

      if (error) throw error;
      const total = count ?? 0;
      return {
        data,
        hasMore:
          total >
          (options?.limit || 0) +
            Number.parseInt(options?.startingAfter || "0"),
        totalCount: total,
      };
    },

    listInvoicesByUserId: async (
      userId: string,
      options?: PaginationOptions
    ): Promise<PaginatedResponse<InvoiceData>> => {
      let customer: DBTable<"billing_customers"> | undefined;
      try {
        customer = await this.db.getCustomerByUserId(userId);
      } catch (error) {
        console.warn("Customer not found");
        return {
          data: [],
          hasMore: false,
          totalCount: 0,
        };
      }

      if (!customer) {
        return {
          data: [],
          hasMore: false,
          totalCount: 0,
        };
      }
      return this.db.listInvoicesByCustomerId(
        customer.gateway_customer_id,
        options
      );
    },

    getProduct: async (productId: string): Promise<ProductData> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_products")
        .select("*, billing_prices(*)")
        .eq("gateway_product_id", productId)
        .eq("gateway_name", this.getName())
        .single();

      if (error) throw error;
      return data;
    },

    getPrice: async (priceId: string): Promise<DBTable<"billing_prices">> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_prices")
        .select("*")
        .eq("gateway_price_id", priceId)
        .eq("gateway_name", this.getName())
        .single();
      if (error) throw error;
      return data;
    },
    listPlans: async (): Promise<Array<ProductData>> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_products")
        .select("*, billing_prices(*)", { count: "exact" })
        .eq("gateway_name", this.getName());

      if (error) throw error;
      return data;
    },

    getOneTimePurchasesByCustomerId: async (
      customerId: string
    ): Promise<OneTimePaymentData[]> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_one_time_payments")
        .select(
          " *, billing_products(*), billing_prices(*), billing_invoices(*)"
        )
        .eq("gateway_customer_id", customerId)
        .eq("gateway_name", this.getName());
      if (error) throw error;
      return data;
    },

    getUserOneTimePurchases: async (
      userId: string
    ): Promise<OneTimePaymentData[]> => {
      let customer: DBTable<"billing_customers"> | undefined;
      try {
        customer = await this.db.getCustomerByUserId(userId);
      } catch (error) {
        console.warn("Customer not found", error);
        return [];
      }
      if (!customer) {
        return [];
      }
      return this.db.getOneTimePurchasesByCustomerId(
        customer.gateway_customer_id
      );
    },

    getUserPaymentMethods: async (
      userId: string
    ): Promise<DBTable<"billing_payment_methods">[]> => {
      const customer = await this.util.getCustomerByUserId(userId);
      if (!customer) {
        return [];
      }

      const { data, error } = await supabaseAdminClient
        .from("billing_payment_methods")
        .select("*")
        .eq("gateway_customer_id", customer.gateway_customer_id)
        .order("is_default", { ascending: false });
      if (error) throw error;
      return data;
    },

    listProducts: async (): Promise<Array<ProductData>> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_products")
        .select("*, billing_prices(*)", { count: "exact" })
        .eq("gateway_name", this.getName());
      if (error) throw error;
      return data;
    },
  };

  util = {
    handleStripeError: (error: unknown) => {
      if (!(error instanceof Error)) {
        throw new Error("Unknown error");
      }
      throw new PaymentGatewayError(
        `StripePaymentGatewayError: ${error.message}`,
        "500",
        this.getName()
      );
    },
    isTestMode: () =>
      process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY?.includes("pk_test") ??
      false,
    createCustomerForUser: async (
      userId: string
    ): Promise<DBTable<"billing_customers">> => {
      try {
        const { data: user, error: userError } =
          await supabaseAdminClient.auth.admin.getUserById(userId);
        if (userError) throw userError;
        if (!user) throw new Error("User not found");
        const maybeEmail = user.user.email;
        if (!maybeEmail) throw new Error("User email not found");
        return this.db.createCustomer(
          {
            billing_email: maybeEmail,
          },
          userId
        );
      } catch (error) {
        console.log("error", error);
        return this.util.handleStripeError(error);
      }
    },

    getCustomerByUserId: async (
      userId: string
    ): Promise<DBTable<"billing_customers"> | null> => {
      const { data, error } = await supabaseAdminClient
        .from("billing_customers")
        .select("*")
        .eq("user_id", userId)
        .eq("gateway_name", this.getName())
        .single();

      if (error) {
        if (error.code === "PGRST116") {
          return null;
        }
        throw error;
      }

      return data;
    },

    supportsFeature: (featureName: string): boolean => {
      const supportedFeatures = [
        "subscriptions",
        "invoices",
        "customer_portal",
        "webhooks",
        "multiple_payment_methods",
      ];
      return supportedFeatures.includes(featureName);
    },
  };

  gateway = {
    createGatewayCustomer: async (
      userData: Partial<CustomerData>
    ): Promise<CustomerData> => {
      const customer = await this.stripe.customers.create(userData);
      const customerEmail = customer.email;
      if (!customerEmail) {
        throw new Error("Customer email not found");
      }
      return {
        id: customer.id,
        email: customerEmail,
        metadata: customer.metadata,
      };
    },

    handleGatewayWebhook: async (
      body: string | Buffer,
      signature: string
    ): Promise<void> => {
      const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
      if (!webhookSecret) {
        throw new StripeWebhookProcessingError(
          "Stripe webhook secret is not configured",
          500
        );
      }

      let event: Stripe.Event;
      try {
        event = this.stripe.webhooks.constructEvent(body, signature, webhookSecret);
      } catch (error) {
        throw new StripeWebhookProcessingError(
          "Invalid Stripe webhook signature or payload",
          400,
          undefined,
          undefined,
          error
        );
      }

      try {
        switch (event.type) {
          case "customer.subscription.created":
          case "customer.subscription.updated":
          case "customer.subscription.deleted":
            await this.handleSubscriptionChange(
              event.data.object as Stripe.Subscription
            );
            return;
          case "invoice.paid":
          case "invoice.payment_failed":
            await this.handleInvoiceChange(event.data.object as Stripe.Invoice);
            return;
          case "customer.updated":
            await this.handleCustomerUpdate(
              event.data.object as Stripe.Customer
            );
            return;
          case "product.created":
          case "product.updated":
            await this.handleProductChange(event.data.object as Stripe.Product);
            return;
          case "price.created":
          case "price.updated":
            await this.handlePriceChange(event.data.object as Stripe.Price);
            return;
          case "charge.succeeded":
            await this.handleChargeChange(event.data.object as Stripe.Charge);
            return;
          default:
            return;
        }
      } catch (error) {
        throw new StripeWebhookProcessingError(
          `Failed to process Stripe webhook event: ${event.type}`,
          500,
          event.id,
          event.type,
          error
        );
      }
    },
    getSubscription: async (
      subscriptionId: string
    ): Promise<GatewaySubscriptionData> => {
      const subscription =
        await this.stripe.subscriptions.retrieve(subscriptionId);
      return {
        id: subscription.id,
        status: subscription.status,
      };
    },
  };

  private async getBillingCustomerByGatewayCustomerId(
    gatewayCustomerId: string
  ): Promise<DBTable<"billing_customers"> | null> {
    const { data, error } = await supabaseAdminClient
      .from("billing_customers")
      .select("*")
      .eq("gateway_customer_id", gatewayCustomerId)
      .eq("gateway_name", this.getName())
      .maybeSingle();

    if (error) throw error;
    return data;
  }

  private async upsertBillingCustomerLink({
    gatewayCustomerId,
    billingEmail,
    linkedUserId,
  }: StripeCustomerLinkInput): Promise<DBTable<"billing_customers">> {
    const { data, error } = await supabaseAdminClient
      .from("billing_customers")
      .upsert(
        {
          gateway_customer_id: gatewayCustomerId,
          gateway_name: this.getName(),
          billing_email: billingEmail,
          user_id: linkedUserId,
        },
        {
          onConflict: "gateway_name,gateway_customer_id",
        }
      )
      .select("*")
      .single();

    if (error) throw error;
    return data;
  }

  private async fetchStripeCustomer(
    customerReference:
      | string
      | Stripe.Customer
      | Stripe.DeletedCustomer
      | null
      | undefined
  ): Promise<Stripe.Customer | null> {
    if (!customerReference) return null;
    if (typeof customerReference === "string") {
      const customer = await this.stripe.customers.retrieve(customerReference);
      if ("deleted" in customer && customer.deleted) return null;
      return customer;
    }

    if ("deleted" in customerReference && customerReference.deleted) {
      return null;
    }

    return customerReference;
  }

  private async ensureBillingCustomerLink(
    customerReference:
      | string
      | Stripe.Customer
      | Stripe.DeletedCustomer
      | null
      | undefined
  ): Promise<DBTable<"billing_customers">> {
    const stripeCustomer = await this.fetchStripeCustomer(customerReference);
    if (!stripeCustomer) {
      throw new Error("Stripe customer not found");
    }

    const existingCustomer = await this.getBillingCustomerByGatewayCustomerId(
      stripeCustomer.id
    );
    const metadataUserId = stripeCustomer.metadata?.user_id?.trim() || null;
    const fallbackUserId = stripeCustomer.email
      ? await superAdminGetUserIdByEmail(stripeCustomer.email)
      : null;
    const linkedUserId =
      metadataUserId ?? fallbackUserId ?? existingCustomer?.user_id ?? null;
    const billingEmail = stripeCustomer.email ?? existingCustomer?.billing_email;

    if (!billingEmail) {
      throw new Error("Stripe customer email not found");
    }

    return this.upsertBillingCustomerLink({
      gatewayCustomerId: stripeCustomer.id,
      billingEmail,
      linkedUserId,
    });
  }

  private async handleSubscriptionChange(subscription: Stripe.Subscription) {
    const billingCustomer = await this.ensureBillingCustomerLink(
      subscription.customer
    );
    const stripeCustomerId = billingCustomer.gateway_customer_id;

    const firstItem = subscription.items.data[0];
    if (!firstItem) {
      throw new Error("Subscription line item not found");
    }

    const { product } = firstItem.price;

    const { error } = await supabaseAdminClient
      .from("billing_subscriptions")
      .upsert(
        {
          gateway_customer_id: stripeCustomerId,
          gateway_name: this.getName(),
          gateway_subscription_id: subscription.id,
          gateway_product_id:
            typeof product === "string" ? product : product.id,
          status: subscription.status,
          current_period_start: new Date(
            firstItem.current_period_start * 1000
          ).toISOString(),
          current_period_end: new Date(
            firstItem.current_period_end * 1000
          ).toISOString(),
          currency: subscription.currency,
          is_trial: subscription.trial_end !== null,
          cancel_at_period_end: subscription.cancel_at_period_end,
          quantity: firstItem.quantity,
          gateway_price_id: firstItem.price.id,
        },
        {
          onConflict: "gateway_name,gateway_subscription_id",
        }
      );

    if (error) throw error;
  }

  private async handleInvoiceChange(invoice: Stripe.Invoice) {
    const billingCustomer = await this.ensureBillingCustomerLink(
      invoice.customer
    );
    const customerId = billingCustomer.gateway_customer_id;

    const dueDate = invoice.due_date;
    const paidDate = invoice.status_transitions.paid_at;
    const firstLine = invoice.lines.data[0];
    const priceId = firstLine?.pricing?.price_details?.price ?? null;
    const productId =
      firstLine?.pricing?.price_details?.product ?? null;

    const invoiceId = invoice.id;
    if (!invoiceId) {
      throw new Error("Invoice ID not found");
    }

    const { error } = await supabaseAdminClient.from("billing_invoices").upsert(
      {
        gateway_customer_id: customerId,
        gateway_name: this.getName(),
        gateway_invoice_id: invoiceId,
        amount: invoice.total,
        currency: invoice.currency,
        status: invoice.status ?? "unknown",
        due_date: dueDate ? new Date(dueDate * 1000).toISOString() : null,
        paid_date: paidDate ? new Date(paidDate * 1000).toISOString() : null,
        hosted_invoice_url: invoice.hosted_invoice_url,
        gateway_price_id: priceId,
        gateway_product_id: productId,
      },
      {
        onConflict: "gateway_name,gateway_invoice_id",
      }
    );

    if (error) throw error;

    const invoiceLines = invoice.lines.data;
    const isSubscriptionRelated =
      invoice.billing_reason === "subscription_cycle" ||
      invoice.billing_reason === "subscription_create" ||
      invoice.billing_reason === "subscription_update" ||
      invoice.billing_reason === "subscription_threshold" ||
      invoice.billing_reason === "subscription";
    if (invoiceLines.length > 0) {
      const line = invoiceLines[0];
      if (line.pricing?.price_details && !isSubscriptionRelated) {
        // this is a one-time charge
        // we don't need to handle subscription charges since subscription tables handle that.
        // this should have a charge field
        let chargeId: string | null = null;

        // Try to get charge ID from invoice (if available)
        if ("charge" in invoice && invoice.charge) {
          chargeId = typeof invoice.charge === "string" ? invoice.charge : null;
        }

        const priceId = line.pricing?.price_details?.price;
        const productId = line.pricing?.price_details?.product;

        if (!(priceId && productId)) {
          return;
        }

        // If no direct charge ID, try to get it from payment intent
        if (
          !chargeId &&
          "payment_intent" in invoice &&
          invoice.payment_intent
        ) {
          try {
            let paymentIntentId: string;
            if (typeof invoice.payment_intent === "string") {
              paymentIntentId = invoice.payment_intent;
            } else if (
              invoice.payment_intent &&
              typeof invoice.payment_intent === "object" &&
              "id" in invoice.payment_intent
            ) {
              const paymentIntentObj = invoice.payment_intent;
              if (typeof paymentIntentObj.id === "string") {
                paymentIntentId = paymentIntentObj.id;
              } else {
                throw new Error("Invalid payment intent ID format");
              }
            } else {
              throw new Error("Invalid payment intent format");
            }

            const paymentIntent =
              await this.stripe.paymentIntents.retrieve(paymentIntentId);

            // Get the latest charge from the payment intent
            if (paymentIntent.latest_charge) {
              chargeId =
                typeof paymentIntent.latest_charge === "string"
                  ? paymentIntent.latest_charge
                  : paymentIntent.latest_charge.id;
            }
          } catch (error) {
            console.warn("Failed to retrieve payment intent:", error);
          }
        }

        // If still no charge ID, try to find charges for this invoice
        if (!chargeId) {
          try {
            const charges = await this.stripe.charges.list({
              limit: 10, // Increase limit to search more thoroughly
            });

            // Look for a charge that references this invoice
            const invoiceCharge = charges.data.find(
              (charge) =>
                ("invoice" in charge && charge.invoice === invoice.id) ||
                charge.metadata?.invoice_id === invoice.id
            );

            if (invoiceCharge) {
              chargeId = invoiceCharge.id;
            }
          } catch (error) {
            console.warn("Failed to search for charges:", error);
          }
        }

        if (!chargeId) {
          return;
        }

        const charge = await this.stripe.charges.retrieve(chargeId);
        if (!invoice.id) {
          throw new Error("Invoice ID is required for one-time payment record");
        }

        const upsertData = {
          charge_date: new Date(charge.created * 1000).toISOString(),
          gateway_invoice_id: invoice.id,
          gateway_price_id: priceId,
          gateway_product_id: productId,
          gateway_customer_id: customerId,
          gateway_name: this.getName(),
          gateway_charge_id: chargeId,
          amount: line.amount,
          currency: line.currency,
          status: String(charge.status),
        };

        const { error: createChargeError } = await supabaseAdminClient
          .from("billing_one_time_payments")
          .upsert(upsertData, {
            onConflict: "gateway_charge_id",
          });

        if (createChargeError) throw createChargeError;
      }
    }
  }

  private async handleCustomerUpdate(customer: Stripe.Customer) {
    await this.ensureBillingCustomerLink(customer);
  }

  private async handleProductChange(product: Stripe.Product) {
    const { error } = await supabaseAdminClient.from("billing_products").upsert(
      {
        gateway_product_id: product.id,
        gateway_name: this.getName(),
        name: product.name,
        description: product.description,
        is_visible_in_ui: product.active,
        features: product.metadata.features,
        active: product.active,
      },
      {
        onConflict: "gateway_product_id,gateway_name",
      }
    );

    if (error) throw error;
  }

  private async handlePriceChange(price: Stripe.Price) {
    const { error } = await supabaseAdminClient.from("billing_prices").upsert(
      {
        gateway_product_id: price.product as string,
        gateway_name: this.getName(),
        gateway_price_id: price.id,
        currency: price.currency,
        amount: price.unit_amount ?? 0,
        recurring_interval: price.recurring?.interval ?? "month",
        recurring_interval_count: price.recurring?.interval_count ?? 1,
        active: price.active,
      },
      {
        onConflict: "gateway_name,gateway_price_id",
      }
    );

    if (error) throw error;
  }

  private async handleChargeChange(charge: Stripe.Charge) {
    const { data: chargeExists, error: chargeExistsError } =
      await supabaseAdminClient
        .from("billing_one_time_payments")
        .select("gateway_charge_id")
        .eq("gateway_charge_id", charge.id)
        .eq("gateway_name", this.getName());
    if (chargeExistsError) throw chargeExistsError;
    if ((chargeExists?.length ?? 0) === 0) {
      return;
    }

    const { error } = await supabaseAdminClient
      .from("billing_one_time_payments")
      .update({
        amount: charge.amount,
        currency: charge.currency,
        status: charge.status,
        charge_date: new Date(charge.created * 1000).toISOString(),
      })
      .eq("gateway_charge_id", charge.id)
      .eq("gateway_name", this.getName());

    if (error) throw error;
  }

  anonScope = {
    /**
     * List all products that are visible to the user.
     */
    listAllProducts: async (): Promise<ProductAndPrice[]> => {
      const { data: products, error } = await supabaseAnonClient
        .from("billing_products")
        .select("*, billing_prices(*)")
        .eq("gateway_name", this.getName())
        .eq("is_visible_in_ui", true);
      if (error) throw error;

      const productsAndPrices: ProductAndPrice[] = [];

      for (const product of products) {
        const { billing_prices, ...coreProduct } = product;
        billing_prices.forEach((price) => {
          productsAndPrices.push({
            product: coreProduct,
            price,
          });
        });
      }
      return productsAndPrices;
    },
    /**
     * List all subscription products that are visible to the user.
     */
    listAllSubscriptionProducts: async (): Promise<
      Dictionary<ProductAndPrice[]>
    > => {
      const { data: products, error } = await supabaseAnonClient
        .from("billing_products")
        .select("*, billing_prices(*)")
        .eq("gateway_name", this.getName())
        .eq("is_visible_in_ui", true)
        .eq("active", true)
        .eq("billing_prices.active", true);
      if (error) throw error;

      const productsAndPrices: ProductAndPrice[] = [];

      for (const product of products) {
        const { billing_prices, ...coreProduct } = product;
        billing_prices.forEach((price) => {
          productsAndPrices.push({
            product: coreProduct,
            price,
          });
        });
      }

      const groupedProductsAndPrices = groupBy(
        productsAndPrices,
        "price.recurring_interval"
      );

      return groupedProductsAndPrices;
    },
    /**
     * List all one-time products that are visible to the user.
     */
    listAllOneTimeProducts: async (): Promise<ProductAndPrice[]> => {
      const { data: products, error } = await supabaseAnonClient
        .from("billing_products")
        .select("*, billing_prices(*)")
        .eq("billing_prices.recurring_interval", "one-time")
        .eq("gateway_name", this.getName())
        .eq("is_visible_in_ui", true)
        .eq("active", true)
        .eq("billing_prices.active", true);
      if (error) throw error;
      const productsAndPrices: ProductAndPrice[] = [];

      for (const product of products) {
        const { billing_prices, ...coreProduct } = product;
        billing_prices.forEach((price) => {
          productsAndPrices.push({
            product: coreProduct,
            price,
          });
        });
      }
      return productsAndPrices;
    },
  };

  userScope = {
    /**
     * Fetches the database subscription for a given user.
     *
     * @param userId - The unique identifier of the user.
     * @returns A promise that resolves to the billing subscription data or null if not found.
     */
    getUserSubscriptions: async (userId: string): Promise<SubscriptionData[]> =>
      this.db.getSubscriptionsByUserId(userId),

    /**
     * Retrieves all one-time purchases for a given user.
     *
     * @param userId - The unique identifier of the user.
     * @returns A promise that resolves to an array of billing payment data.
     */
    getUserOneTimePurchases: async (
      userId: string
    ): Promise<OneTimePaymentData[]> => this.db.getUserOneTimePurchases(userId),

    /**
     * Fetches all invoices for a given user.
     *
     * @param userId - The unique identifier of the user.
     * @returns A promise that resolves to a paginated response of billing invoice data.
     */
    getUserInvoices: async (
      userId: string
    ): Promise<PaginatedResponse<InvoiceData>> =>
      this.db.listInvoicesByUserId(userId),

    /**
     * Retrieves all payment methods associated with a given user.
     *
     * @param userId - The unique identifier of the user.
     * @returns A promise that resolves to an array of PaymentMethodData.
     */
    getUserPaymentMethods: async (
      userId: string
    ): Promise<DBTable<"billing_payment_methods">[]> =>
      this.db.getUserPaymentMethods(userId),

    /**
     * Fetches the customer data for a given user.
     *
     * @param userId - The unique identifier of the user.
     * @returns A promise that resolves to the billing customer data.
     */
    getUserCustomer: async (
      userId: string
    ): Promise<DBTable<"billing_customers">> =>
      this.db.getCustomerByUserId(userId),

    createGatewayCheckoutSession: async ({
      userId,
      priceId,
      options,
    }: {
      userId: string;
      priceId: string;
      options?: CheckoutSessionOptions;
    }): Promise<CheckoutSessionData> => {
      let customer = await this.util.getCustomerByUserId(userId);
      if (!customer) {
        customer = await this.util.createCustomerForUser(userId);
      }

      const { freeTrialDays } = options ?? {};
      const price = await this.db.getPrice(priceId);
      if (!price) {
        throw new Error("Price not found");
      }

      const sessionConfig: Stripe.Checkout.SessionCreateParams = {
        customer: customer.gateway_customer_id,
        payment_method_types: ["card"],
        billing_address_collection: "required",
        line_items: [{ price: priceId, quantity: 1 }],
        allow_promotion_codes: true,
        success_url: toSiteURL("/dashboard/settings/billing?success=true"),
        cancel_url: toSiteURL("/dashboard/settings/billing?cancel=true"),
      };

      if (price.recurring_interval === "one-time") {
        sessionConfig.mode = "payment";
        sessionConfig.invoice_creation = {
          enabled: true,
        };
      } else {
        sessionConfig.mode = "subscription";
        sessionConfig.subscription_data = {
          trial_settings: {
            end_behavior: {
              missing_payment_method: "cancel",
            },
          },
        };

        if (freeTrialDays) {
          sessionConfig.subscription_data.trial_period_days =
            freeTrialDays ?? 14;
        }
      }

      const session = await this.stripe.checkout.sessions.create(sessionConfig);

      if (!session.url) {
        throw new Error("Checkout session URL not found");
      }

      return {
        id: session.id,
        url: session.url,
      };
    },

    createGatewayCustomerPortalSession: async (
      userId: string,
      returnUrl: string
    ): Promise<CustomerPortalData> => {
      const customer = await this.util.getCustomerByUserId(userId);
      if (!customer) {
        throw new Error("Customer not found");
      }
      const session = await this.stripe.billingPortal.sessions.create({
        customer: customer.gateway_customer_id,
        return_url: returnUrl,
      });

      return {
        url: session.url,
      };
    },
  };

  superAdminScope = {
    syncCustomers: async (): Promise<void> => {
      try {
        const { data: customers, error: fetchError } = await supabaseAdminClient
          .from("billing_customers")
          .select("*")
          .eq("gateway_name", this.getName());

        if (fetchError) throw fetchError;
        const stripeCustomers = await this.stripe.customers.list({
          email: customers.map((customer) => customer.billing_email).join(","),
        });
        const stripeCustomerMap = new Map<string, string>();

        stripeCustomers.data.forEach((customer) => {
          if (customer.email) {
            stripeCustomerMap.set(customer.email, customer.id);
          }
        });

        for (const customer of customers) {
          if (stripeCustomerMap.has(customer.billing_email)) {
            const stripeCustomerId = stripeCustomerMap.get(
              customer.billing_email
            );
            if (stripeCustomerId) {
              await this.db.updateCustomer(stripeCustomerId, {
                gateway_customer_id: stripeCustomerMap.get(
                  customer.billing_email
                ),
              });
            }
          }
        }

        for (const stripeCustomer of stripeCustomers.data) {
          if (
            stripeCustomer.email &&
            !customers.some(
              (customer) => customer.billing_email === stripeCustomer.email
            )
          ) {
            await this.db.createCustomer(
              {
                billing_email: stripeCustomer.email,
              },
              stripeCustomer.metadata.user_id
            );
          }
        }
      } catch (error) {
        this.util.handleStripeError(error);
      }
    },

    syncProducts: async (): Promise<void> => {
      const [stripePrices, stripeProducts] = await Promise.all([
        this.stripe.prices.list({ active: true }),
        this.stripe.products.list({ active: true }),
      ]);

      const productsToUpsert: DBTableInsertPayload<"billing_products">[] =
        stripeProducts.data.map((stripeProduct) => ({
          gateway_product_id: stripeProduct.id,
          gateway_name: this.getName(),
          name: stripeProduct.name,
          description: stripeProduct.description,
          active: stripeProduct.active,
          features: stripeProduct.metadata.features
            ? JSON.parse(stripeProduct.metadata.features)
            : null,
        }));

      const validStripePrices = stripePrices.data.filter((stripePrice) =>
        productsToUpsert.some(
          (product) => product.gateway_product_id === stripePrice.product
        )
      );
      const { error: upsertError } = await supabaseAdminClient
        .from("billing_products")
        .upsert(productsToUpsert, {
          onConflict: "gateway_product_id,gateway_name",
        });
      if (upsertError) throw upsertError;

      const pricesToUpsert: DBTableInsertPayload<"billing_prices">[] =
        validStripePrices.map((stripePrice) => ({
          gateway_product_id: stripePrice.product as string,
          currency: stripePrice.currency,
          amount: stripePrice.unit_amount ?? 0,
          recurring_interval: stripePrice.recurring?.interval ?? "one-time",
          recurring_interval_count: stripePrice.recurring?.interval_count ?? 1,
          gateway_name: this.getName(),
          gateway_price_id: stripePrice.id,
          active: stripePrice.active,
        }));

      const { error: priceUpsertError } = await supabaseAdminClient
        .from("billing_prices")
        .upsert(pricesToUpsert, { onConflict: "gateway_name,gateway_price_id" });
      if (priceUpsertError) {
        console.log("priceUpsertError", priceUpsertError);
        throw priceUpsertError;
      }
    },

    toggleProductVisibility: async (
      productId: string,
      isVisible: boolean
    ): Promise<void> => {
      await supabaseAdminClient
        .from("billing_products")
        .update({ is_visible_in_ui: isVisible })
        .eq("gateway_product_id", productId)
        .eq("gateway_name", this.getName());
    },

    listAllProducts: async (): Promise<ProductData[]> => this.db.listProducts(),
    getMRRBetween: async (startDate: Date, endDate: Date): Promise<number> => {
      const { data: subscriptionPrices, error: pricesError } =
        await supabaseAdminClient
          .from("billing_prices")
          .select("gateway_price_id, currency, amount")
          .eq("gateway_name", this.getName())
          .neq("recurring_interval", "one-time");

      if (pricesError) throw pricesError;

      const priceIds = subscriptionPrices.map(
        (price) => price.gateway_price_id
      );
      const { data: invoices, error: invoicesError } = await supabaseAdminClient
        .from("billing_invoices")
        .select("amount, currency, gateway_price_id")
        .eq("gateway_name", this.getName())
        .eq("status", "paid")
        .in("gateway_price_id", priceIds)
        .gte("paid_date", startDate.toISOString())
        .lte("paid_date", endDate.toISOString());

      if (invoicesError) throw invoicesError;

      const mrr = invoices.reduce((acc, invoice) => {
        const price = subscriptionPrices.find(
          (p) => p.gateway_price_id === invoice.gateway_price_id
        );
        if (!price) return acc;

        const amount =
          invoice.currency === "usd" ? invoice.amount / 100 : invoice.amount;
        return acc + convertAmountToUSD(amount, invoice.currency);
      }, 0);

      return mrr;
    },

    /**
     * This gets current active subscription revenue.
     */
    getCurrentMRR: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 30);

      return this.superAdminScope.getRevenueBetween(startDate, endDate);
    },

    getLastMonthMRR: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 60);
      endDate.setDate(endDate.getDate() - 30);

      return this.superAdminScope.getRevenueBetween(startDate, endDate);
    },

    getRevenueBetween: async (
      startDate: Date,
      endDate: Date
    ): Promise<number> => {
      const { data: invoices, error } = await supabaseAdminClient
        .from("billing_invoices")
        .select("amount, currency")
        .eq("gateway_name", this.getName())
        .gte("paid_date", startDate.toISOString())
        .lte("paid_date", endDate.toISOString())
        .eq("status", "paid");

      if (error) throw error;

      const totalRevenue = invoices.reduce((acc, invoice) => {
        const amount =
          invoice.currency === "usd" ? invoice.amount / 100 : invoice.amount;
        return acc + convertAmountToUSD(amount, invoice.currency);
      }, 0);

      return totalRevenue;
    },
    getCurrentMonthRevenue: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 30);

      return this.superAdminScope.getRevenueBetween(startDate, endDate);
    },

    getLastMonthRevenue: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 60);
      endDate.setDate(endDate.getDate() - 30);

      return this.superAdminScope.getRevenueBetween(startDate, endDate);
    },

    getOneTimePurchasesBetween: async (
      startDate: Date,
      endDate: Date
    ): Promise<number> => {
      const { data: invoices, error } = await supabaseAdminClient
        .from("billing_one_time_payments")
        .select("amount, currency")
        .eq("gateway_name", this.getName())
        .gte("charge_date", startDate.toISOString())
        .lte("charge_date", endDate.toISOString())
        .eq("status", "succeeded");

      if (error) throw error;

      const totalRevenue = invoices.reduce((acc, invoice) => {
        const amount =
          invoice.currency === "usd" ? invoice.amount / 100 : invoice.amount;
        return acc + convertAmountToUSD(amount, invoice.currency);
      }, 0);

      return totalRevenue;
    },

    getCurrentMonthOneTimePurchaseRevenue: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 30);

      return this.superAdminScope.getOneTimePurchasesBetween(
        startDate,
        endDate
      );
    },

    getLastMonthOneTimePurchaseRevenue: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 60);
      endDate.setDate(endDate.getDate() - 30);

      return this.superAdminScope.getOneTimePurchasesBetween(
        startDate,
        endDate
      );
    },

    getRevenueByMonthBetween: async (
      startDate: Date,
      endDate: Date
    ): Promise<{ month: Date; revenue: number }[]> => {
      const { data: invoices, error } = await supabaseAdminClient
        .from("billing_invoices")
        .select("amount, currency, paid_date")
        .eq("gateway_name", this.getName())
        .gte("paid_date", startDate.toISOString())
        .lte("paid_date", endDate.toISOString())
        .eq("status", "paid");

      if (error) throw error;

      const revenueByMonth: { [key: string]: number } = {};

      // Initialize all months with zero revenue
      const currentMonth = new Date(startDate);
      while (currentMonth <= endDate) {
        const monthKey = currentMonth.toISOString().slice(0, 7); // YYYY-MM
        revenueByMonth[monthKey] = 0;
        currentMonth.setMonth(currentMonth.getMonth() + 1);
      }

      invoices.forEach((invoice) => {
        if (invoice.paid_date) {
          const month = new Date(invoice.paid_date).toISOString().slice(0, 7); // YYYY-MM
          const amount =
            invoice.currency === "usd" ? invoice.amount / 100 : invoice.amount;
          const revenue = convertAmountToUSD(amount, invoice.currency);
          revenueByMonth[month] += revenue;
        }
      });

      return Object.entries(revenueByMonth)
        .map(([month, revenue]) => ({
          month: new Date(month),
          revenue,
        }))
        .sort((a, b) => a.month.getTime() - b.month.getTime());
    },

    getSubscriberCountBetween: async (
      startDate: Date,
      endDate: Date
    ): Promise<number> => {
      const { data: subscriptionPrices, error: pricesError } =
        await supabaseAdminClient
          .from("billing_prices")
          .select("gateway_price_id, currency, amount")
          .eq("gateway_name", this.getName())
          .neq("recurring_interval", "one-time");
      if (pricesError) throw pricesError;
      const priceIds = subscriptionPrices.map(
        (price) => price.gateway_price_id
      );
      console.log("priceIds", priceIds);
      const { count: invoiceCount, error: invoicesError } =
        await supabaseAdminClient
          .from("billing_invoices")
          .select("*", { count: "exact", head: true })
          .eq("gateway_name", this.getName())
          .eq("status", "paid")
          .in("gateway_price_id", priceIds)
          .gte("paid_date", startDate.toISOString())
          .lte("paid_date", endDate.toISOString());

      if (invoicesError) throw invoicesError;
      return invoiceCount || 0;
    },

    getCurrentMonthlySubscriptionCount: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 30);

      return this.superAdminScope.getSubscriberCountBetween(startDate, endDate);
    },

    getLastMonthSubscriptionCount: async (): Promise<number> => {
      const endDate = new Date();
      const startDate = new Date(endDate);
      startDate.setDate(startDate.getDate() - 60);
      endDate.setDate(endDate.getDate() - 30);

      return this.superAdminScope.getSubscriberCountBetween(startDate, endDate);
    },

    getSubscriptionsByMonthBetween: async (
      startDate: Date,
      endDate: Date
    ): Promise<{ month: Date; subscriptions: number }[]> => {
      const { data: subscriptions, error } = await supabaseAdminClient
        .from("billing_subscriptions")
        .select("current_period_start")
        .eq("gateway_name", this.getName())
        .gte("current_period_start", startDate.toISOString())
        .lte("current_period_start", endDate.toISOString());

      if (error) throw error;

      const subscriptionsByMonth: { [key: string]: number } = {};

      // Initialize all months with zero subscriptions
      const currentMonth = new Date(startDate);
      while (currentMonth <= endDate) {
        const monthKey = currentMonth.toISOString().slice(0, 7); // YYYY-MM
        subscriptionsByMonth[monthKey] = 0;
        currentMonth.setMonth(currentMonth.getMonth() + 1);
      }

      // Count subscriptions for each month
      subscriptions.forEach((subscription) => {
        const month = new Date(subscription.current_period_start)
          .toISOString()
          .slice(0, 7); // YYYY-MM
        subscriptionsByMonth[month]++;
      });

      return Object.entries(subscriptionsByMonth)
        .map(([month, count]) => ({
          month: new Date(month),
          subscriptions: count,
        }))
        .sort((a, b) => a.month.getTime() - b.month.getTime());
    },

    getCurrentRevenueByProduct: async (): Promise<
      { productId: string; revenue: number }[]
    > => {
      const { data: subscriptions, error } = await supabaseAdminClient
        .from("billing_subscriptions")
        .select(
          `
          gateway_product_id,
          billing_prices (amount, currency)
        `
        )
        .eq("gateway_name", this.getName())
        .eq("status", "active");

      if (error) throw error;

      const revenueByProduct: { [key: string]: number } = {};

      subscriptions.forEach((subscription) => {
        const price = subscription.billing_prices;
        if (!price) {
          return;
        }
        const amount =
          price.currency === "usd" ? price.amount / 100 : price.amount;
        const revenue = convertAmountToUSD(amount, price.currency);
        revenueByProduct[subscription.gateway_product_id] =
          (revenueByProduct[subscription.gateway_product_id] || 0) + revenue;
      });

      return Object.entries(revenueByProduct).map(([productId, revenue]) => ({
        productId,
        revenue,
      }));
    },
    listCurrentMonthInvoices: async (): Promise<InvoiceData[]> => {
      const startDate = new Date();
      const endDate = new Date();
      startDate.setDate(startDate.getDate() - 30);
      const { data: invoices, error } = await supabaseAdminClient
        .from("billing_invoices")
        .select("*, billing_prices(*), billing_products(*)")
        .eq("gateway_name", this.getName())
        .gte("paid_date", startDate.toISOString())
        .lte("paid_date", endDate.toISOString());
      if (error) throw error;
      return invoices;
    },
    listCurrentMonthSubscriptions: async (): Promise<SubscriptionData[]> => {
      const startDate = new Date();
      const endDate = new Date();
      startDate.setDate(startDate.getDate() - 30);
      const { data: subscriptions, error } = await supabaseAdminClient
        .from("billing_subscriptions")
        .select("*, billing_prices(*), billing_products(*)")
        .eq("gateway_name", this.getName())
        .gte("current_period_start", startDate.toISOString())
        .lte("current_period_start", endDate.toISOString());
      if (error) throw error;
      return subscriptions;
    },
    listCustomers: async (): Promise<DBTable<"billing_customers">[]> => {
      const { data: customers, error } = await supabaseAdminClient
        .from("billing_customers")
        .select("*")
        .eq("gateway_name", this.getName());
      if (error) throw error;
      return customers;
    },
  };
}
