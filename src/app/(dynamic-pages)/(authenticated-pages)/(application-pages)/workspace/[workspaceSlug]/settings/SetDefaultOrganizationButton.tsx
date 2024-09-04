'use client';
import { Button } from '@/components/ui/button';
import { setDefaultOrganization } from '@/data/user/organizations';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';

export function SetDefaultOrganizationButton({
  organizationId,
}: {
  organizationId: string;
}) {
  const { mutate, isLoading } = useSAToastMutation(
    async () => {
      return await setDefaultOrganization(organizationId);
    },
    {
      loadingMessage: 'Setting as default organization...',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to set as default organization ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to set as default organization';
        }
      },
      successMessage: 'Organization set as default!',
    },
  );
  return (
    <Button aria-disabled={isLoading} onClick={() => mutate()}>
      {isLoading ? 'Updating...' : 'Set as default'}
    </Button>
  );
}
