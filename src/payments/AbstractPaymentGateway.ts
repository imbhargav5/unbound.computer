import { DBTable, Enum } from "@/types";

export class PaymentGatewayError extends Error {
  constructor(message: string, public code: string, public gateway: string) {
    super(message);
    this.name = 'PaymentGatewayError';
  }
}

export interface PaginationOptions {
  limit?: number;
  startingAfter?: string;
  endingBefore?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  hasMore: boolean;
  totalCount?: number;
}

export type CustomerData = {
  id?: string;
  email: string;
  metadata?: { [key: string]: any };
}

export interface SubscriptionData {
  id: string;
  customerId: string;
  planId: string;
  status: Enum<'subscription_status'>
  currentPeriodStart: Date;
  currentPeriodEnd: Date;
  cancelAtPeriodEnd: boolean;
}

export type PlanData = DBTable<'billing_plans'> & {
  billing_plan_prices: DBTable<'billing_plan_prices'>[];
};

export interface CheckoutSessionData {
  id: string;
  url: string;
}

export interface CustomerPortalData {
  url: string;
}

export type InvoiceData = DBTable<'billing_invoices'>

export interface PaymentMethodData {
  id: string;
  customerId: string;
  type: 'card' | 'bank_account' | 'other';
  last4: string;
  expiryMonth?: number;
  expiryYear?: number;
}

export type CheckoutSessionOptions = {
  isTrial?: boolean;
}

export abstract class PaymentGateway {
  abstract getName(): string;

  abstract db: {
    createCustomer(userData: Partial<DBTable<'billing_customers'>>, organizationId: string): Promise<DBTable<'billing_customers'>>;
    getCustomer(customerId: string): Promise<DBTable<'billing_customers'>>;
    hasCustomer(customerId: string): Promise<boolean>
    updateCustomer(customerId: string, updateData: Partial<DBTable<'billing_customers'>>): Promise<DBTable<'billing_customers'>>;
    deleteCustomer(customerId: string): Promise<void>;
    listCustomers(options?: PaginationOptions): Promise<PaginatedResponse<DBTable<'billing_customers'>>>;
    // Subscription methods
    getSubscription(subscriptionId: string): Promise<SubscriptionData>;
    listSubscriptions(customerId: string, options?: PaginationOptions): Promise<PaginatedResponse<SubscriptionData>>;
    // Invoice methods
    getInvoice(invoiceId: string): Promise<InvoiceData>;
    listInvoices(customerId: string, options?: PaginationOptions): Promise<PaginatedResponse<InvoiceData>>;
    // Plan methods
    getPlan(planId: string): Promise<PlanData>;
    listPlans(options?: PaginationOptions): Promise<PaginatedResponse<PlanData>>;
  }

  abstract util: {
    createCustomerForOrganization(organizationId: string): Promise<DBTable<'billing_customers'>>;
    getCustomerByOrganizationId(organizationId: string): Promise<DBTable<'billing_customers'> | null>;
    supportsFeature(featureName: string): boolean;
  }

  abstract gateway: {
    createCustomer(userData: Partial<CustomerData>): Promise<CustomerData>;
    // Webhook methods
    handleWebhook(body: any, signature: string): Promise<void>;
    // Checkout methods
    createCheckoutSession(organizationId: string, planId: string, options?: CheckoutSessionOptions): Promise<CheckoutSessionData>;
    // Customer portal methods
    createCustomerPortalSession(gatewayCustomerId: string, returnUrl: string): Promise<CustomerPortalData>;
    syncPlans(): Promise<void>;
  }

}
