'use client';

import { Button } from '@/components/ui/button';

import { generateUnkeyToken } from '@/data/user/unkey';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { ViewApiKeyDialog } from './ViewApiKeyDialog';

export function GenerateApiKey() {
  const router = useRouter();
  const { mutate, isLoading } = useSAToastMutation(async () => {
    return await generateUnkeyToken();
  }, {
    onSuccess: (response) => {
      if (response.status === 'success' && response.data) {
        setStep('copy_modal');
        setKeyPreview(response.data.key);
      }
    },
    errorMessage(error) {
      try {
        if (error instanceof Error) {
          return String(error.message);
        }
        return `Failed to generate API Key ${String(error)}`;
      } catch (_err) {
        console.warn(_err);
        return 'Failed to generate API Key';
      }
    },
  });

  const [step, setStep] = useState<'form' | 'copy_modal' | 'complete'>('form');
  const [keyPreview, setKeyPreview] = useState<string | null>(null);

  return (
    <>
      <form
        className=" max-w-sm"
        onSubmit={(event) => {
          event.preventDefault();
          mutate();
        }}
      >
        <div className="space-y-2">
          <Button
            type="submit"
            size="lg"
            className="block w-full"
            aria-disabled={isLoading}
          >
            {isLoading ? 'Generating new API Key...' : 'Generate API Key'}
          </Button>
        </div>
      </form>

      {step === 'copy_modal' && keyPreview ? (
        <ViewApiKeyDialog
          onCompleted={() => {
            setStep('complete');
            router.refresh();
          }}
          apiKey={keyPreview}
        />
      ) : null}
    </>
  );
}
