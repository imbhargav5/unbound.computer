'use client';

import { T } from '@/components/ui/Typography';
import { Button } from '@/components/ui/button';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import {
  createSubSuccessCB,
  createTrialSubSuccessCB,
  manageSubsSuccessCB,
} from '@/lib/payments/paymentGatewayUtils';
import {
  createSubscription,
  manageSubscription,
  startTrial,
} from '@/lib/payments/paymentUtilsServer';
import { ExternalLink } from 'lucide-react';

export function CreateSubscriptionButton({
  organizationId,
  priceId,
}: {
  organizationId: string;
  priceId: string;
}) {
  const { mutate, isLoading } = useSAToastMutation(
    async () => {
      return await createSubscription(organizationId, priceId);
    },
    {
      loadingMessage: 'Please wait...',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to create subscription ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to create subscription';
        }
      },
      successMessage: 'Redirecting...',
      onSuccess(response) {
        response.status === 'success' && response.data
          ? createSubSuccessCB(response.data)
          : null;
      },
    },
  );

  return (
    <Button
      variant="outline"
      className="w-full"
      onClick={() => {
        mutate();
      }}
    >
      {isLoading ? 'Loading...' : 'Choose'}
    </Button>
  );
}

export function StartFreeTrialButton({
  organizationId,
  priceId,
}: {
  organizationId: string;
  priceId: string;
}) {
  const { mutate, isLoading } = useSAToastMutation(
    async () => {
      return await startTrial(organizationId, priceId);
    },
    {
      loadingMessage: 'Please wait...',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to create a trial subscription ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to create a trial subscription';
        }
      },
      successMessage: 'Redirecting...',
      onSuccess(response) {
        response.status === 'success' && response.data
          ? createTrialSubSuccessCB(response.data)
          : null;
      },
    },
  );

  return (
    <Button
      variant="outline"
      className="w-full"
      onClick={() => {
        mutate();
      }}
    >
      {isLoading ? 'Starting trial...' : 'Start Free Trial'}
    </Button>
  );
}

export function ManageSubscriptionButton({
  organizationId,
}: {
  organizationId: string;
}) {
  const { mutate, isLoading } = useSAToastMutation(
    async () => {
      return await manageSubscription(organizationId);
    },
    {
      loadingMessage: 'Please wait...',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to create a trial subscription ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to create a trial subscription';
        }
      },
      successMessage: 'Redirecting...',
      onSuccess(response) {
        response.status === 'success' && response.data
          ? manageSubsSuccessCB(response.data)
          : null;
      },
    },
  );

  return (
    <div className="space-y-2">
      <Button
        variant="default"
        type="button"
        onClick={() => {
          mutate();
        }}
      >
        <span>{isLoading ? 'Loading...' : 'Manage Subscription'} </span>
        <ExternalLink aria-hidden="true" className="ml-2 w-5 h-5" />{' '}
      </Button>
      <T.P className="text-neutral-500 text-sm">
        Manage your subscription. You can modify, upgrade or cancel your
        membership from here.
      </T.P>
    </div>
  );
}
