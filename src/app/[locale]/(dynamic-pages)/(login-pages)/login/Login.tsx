'use client';

import { EmailConfirmationPendingCard } from '@/components/Auth/EmailConfirmationPendingCard';
import { RedirectingPleaseWaitCard } from '@/components/Auth/RedirectingPleaseWaitCard';
import { RenderProviders } from '@/components/Auth/RenderProviders';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { signInWithProviderAction } from '@/data/auth/auth';
import { useAction } from 'next-safe-action/hooks';
import { useRouter } from 'next/navigation';
import { useRef, useState } from 'react';
import { toast } from 'sonner';
import { MagicLinkLoginForm } from './MagicLinkLoginForm';
import { PasswordLoginForm } from './PasswordLoginForm';

export function Login({
  next,
  nextActionType,
}: {
  next?: string;
  nextActionType?: string;
}) {
  const [emailSentSuccessMessage, setEmailSentSuccessMessage] = useState<string | null>(null);
  const [redirectInProgress, setRedirectInProgress] = useState(false);
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);

  function redirectToDashboard() {
    if (next) {
      router.push(`/auth/callback?next=${next}`);
    } else {
      router.push('/dashboard');
    }
  }

  const { execute: executeProvider, status: providerStatus } = useAction(signInWithProviderAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Requesting login...');
    },
    onSuccess: ({ data }) => {
      if (data) {
        toast.success('Redirecting...', {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        window.location.href = data.url;
      }
    },
    onError: (error) => {
      toast.error('Failed to login', {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
  });

  if (emailSentSuccessMessage) {
    return (
      <EmailConfirmationPendingCard
        type={'login'}
        heading={"Confirmation Link Sent"}
        message={emailSentSuccessMessage}
        resetSuccessMessage={setEmailSentSuccessMessage}
      />
    );
  }

  if (redirectInProgress) {
    return (
      <RedirectingPleaseWaitCard
        message="Please wait while we redirect you to your dashboard."
        heading="Redirecting to Dashboard"
      />
    );
  }

  return (
    <div className="container text-left max-w-lg mx-auto overflow-auto min-h-[470px]">
      <div className="space-y-8 bg-background p-6 rounded-lg shadow dark:border">
        <Tabs defaultValue="password" className="md:min-w-[400px]">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="password">Password</TabsTrigger>
            <TabsTrigger value="magic-link">Magic Link</TabsTrigger>
            <TabsTrigger value="social-login">Social Login</TabsTrigger>
          </TabsList>
          <TabsContent value="password">
            <Card className="border-none shadow-none">
              <CardHeader className="py-6 px-0">
                <CardTitle>Login to NextBase</CardTitle>
                <CardDescription>
                  Login with the account you used to signup.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-2 p-0">
                <PasswordLoginForm
                  next={next}
                  redirectToDashboard={redirectToDashboard}
                  setRedirectInProgress={setRedirectInProgress}
                />
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="magic-link">
            <Card className="border-none shadow-none">
              <CardHeader className="py-6 px-0">
                <CardTitle>Login to NextBase</CardTitle>
                <CardDescription>
                  Login with magic link we will send to your email.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-2 p-0">
                <MagicLinkLoginForm
                  next={next}
                  setEmailSentSuccessMessage={setEmailSentSuccessMessage}
                />
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="social-login">
            <Card className="border-none shadow-none">
              <CardHeader className="py-6 px-0">
                <CardTitle>Login to NextBase</CardTitle>
                <CardDescription>
                  Login with your social account.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-2 p-0">
                <RenderProviders
                  providers={['google', 'github', 'twitter']}
                  isLoading={providerStatus === 'executing'}
                  onProviderLoginRequested={(provider) => executeProvider({ provider, next })}
                />
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
