const exchangeRateMap = {
  'inr': 0.012,
  'usd': 1, // we store cents in the database
  'eur': 1.1,
  'gbp': 1.2,
  'jpy': 0.007,
  'cad': 0.7,
  'aud': 0.6,
  'sgd': 0.7,
  'hkd': 0.1,
  'cny': 0.1,
  'brl': 0.2,
  'mxn': 0.05,
  'zar': 0.05,
  'zwl': 0.00003
}

export function convertAmountToUSD(amount: number, currency: string): number {
  const exchangeRate = exchangeRateMap[currency];
  if (!exchangeRate) {
    throw new Error(`Unsupported currency: ${currency}`);
  }
  return amount * exchangeRate;
}
