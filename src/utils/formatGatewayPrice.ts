import { DBTable } from '@/types';
export function formatGatewayPrice(price: DBTable<'billing_prices'>): string {
  const amount = price.amount ? `$${(price.amount / 100).toFixed(2)}` : 'Custom pricing';
  const intervalCount = price.recurring_interval_count ?? 1;
  const interval = price.recurring_interval && price.recurring_interval !== 'one-time'
    ? `/${intervalCount} ${intervalCount > 1 ? `${price.recurring_interval}s` : price.recurring_interval}`
    : '';

  return `${amount}${interval}`;
}
