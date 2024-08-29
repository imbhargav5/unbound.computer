import { StripePaymentGateway } from '@/payments/StripePaymentGateway';
import { buffer } from 'micro';
import { NextApiRequest, NextApiResponse } from 'next';

export const config = {
  api: {
    bodyParser: false,
  },
};

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method === 'POST') {
    const buf = await buffer(req);
    const sig = req.headers['stripe-signature']

    if (typeof sig !== 'string') {
      return res.status(400).json({ error: 'Invalid signature' });
    }


    const stripeGateway = new StripePaymentGateway();

    try {
      await stripeGateway.handleWebhook(buf, sig);
      res.status(200).json({ received: true });
    } catch (err) {
      console.error('Error processing webhook:', err);
      res.status(400).json({ error: 'Webhook error' });
    }
  } else {
    res.setHeader('Allow', 'POST');
    res.status(405).end('Method Not Allowed');
  }
}
