'use client';

import { useAction } from 'next-safe-action/hooks';
import { useRef, useState } from 'react';
import { toast } from 'sonner';

import { EmailConfirmationPendingCard } from '@/components/Auth/EmailConfirmationPendingCard';
import { RenderProviders } from '@/components/Auth/RenderProviders';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

import { FormInput } from '@/components/form-components/FormInput';
import { Button } from '@/components/ui/button';
import { Form } from '@/components/ui/form';
import { signInWithMagicLinkAction, signInWithProviderAction, signUpWithPasswordAction } from '@/data/auth/auth';
import type { AuthProvider } from '@/types';
import { getSafeActionErrorMessage } from '@/utils/errorMessage';
import { signInWithMagicLinkSchema, signInWithMagicLinkSchemaType, signUpWithPasswordSchema, SignUpWithPasswordSchemaType } from '@/utils/zod-schemas/auth';
import { zodResolver } from '@hookform/resolvers/zod';
import { useHookFormActionErrorMapper } from "@next-safe-action/adapter-react-hook-form/hooks";
import Link from 'next/link';
import { useForm } from 'react-hook-form';

interface SignUpProps {
  next?: string;
  nextActionType?: string;
}

function EmailPasswordForm({ next, setSuccessMessage }: { next?: string, setSuccessMessage: (message: string) => void }) {
  const toastRef = useRef<string | number | undefined>(undefined);


  const signUpWithPasswordMutation = useAction(signUpWithPasswordAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Creating account...');
    },
    onSuccess: ({ data }) => {
      toast.success('Account created!', { id: toastRef.current });
      toastRef.current = undefined;
      setSuccessMessage('A confirmation link has been sent to your email!');
    },
    onError: ({ error }) => {
      const errorMessage = getSafeActionErrorMessage(error, 'Failed to create account');
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });
  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof signUpWithPasswordSchema
  >(signUpWithPasswordMutation.result.validationErrors, { joinBy: "\n" });

  const { execute: executeSignUp, status: signUpStatus } = signUpWithPasswordMutation;

  const form = useForm<SignUpWithPasswordSchemaType>({
    resolver: zodResolver(signUpWithPasswordSchema),
    defaultValues: {
      email: '',
      password: '',
      next
    },
    errors: hookFormValidationErrors,
  });

  const { handleSubmit, formState: { errors }, control } = form;

  const onSubmit = (data: SignUpWithPasswordSchemaType) => {
    executeSignUp({ ...data, next });
  };

  return (
    <Form {...form}>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <FormInput
          id="email"
          label="Email"
          type="email"
          control={control}
          name="email"
          inputProps={{
            autoComplete: 'email',
          }}
        />
        <FormInput
          id="password"
          label="Password"
          type="password"
          control={control}
          name="password"
          inputProps={{
            autoComplete: 'new-password',
          }}
        />
        <Button type="submit" disabled={signUpStatus === 'executing'}>
          {signUpStatus === 'executing' ? 'Signing up...' : 'Sign up'}
        </Button>
        <div className="w-full text-center">
          <div className="text-sm">
            <Link
              href="/login"
              className="font-medium text-muted-foreground hover:text-foreground"
            >
              Already have an account? Log in
            </Link>
          </div>
        </div>
      </form>
    </Form>
  );
}

function EmailForm({ next, setSuccessMessage }: { next?: string, setSuccessMessage: (message: string) => void }) {
  const toastRef = useRef<string | number | undefined>(undefined);

  const signInWithMagicLinkMutation = useAction(signInWithMagicLinkAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Sending magic link...');
    },
    onSuccess: () => {
      toast.success('A magic link has been sent to your email!', { id: toastRef.current });
      toastRef.current = undefined;
      setSuccessMessage('A magic link has been sent to your email!');
    },
    onError: ({ error }) => {
      const errorMessage = getSafeActionErrorMessage(error, 'Failed to send magic link');
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof signInWithMagicLinkSchema
  >(signInWithMagicLinkMutation.result.validationErrors, { joinBy: "\n" });

  const { execute: executeMagicLink, status: magicLinkStatus } = signInWithMagicLinkMutation;

  const form = useForm<signInWithMagicLinkSchemaType>({
    resolver: zodResolver(signInWithMagicLinkSchema),
    defaultValues: {
      email: '',
      shouldCreateUser: true,
      next
    },
    errors: hookFormValidationErrors,
  });

  const { handleSubmit, control } = form;

  const onSubmit = (data: signInWithMagicLinkSchemaType) => {
    executeMagicLink(data);
  };

  return (
    <Form {...form}>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" data-testid="magic-link-form">
        <FormInput
          id="sign-up-email"
          label="Email address"
          type="email"
          control={control}
          name="email"
          inputProps={{
            placeholder: 'placeholder@email.com',
            disabled: magicLinkStatus === 'executing',
            autoComplete: 'email',
          }}
        />
        <Button className="w-full" type="submit" disabled={magicLinkStatus === 'executing'}>
          {magicLinkStatus === 'executing' ? 'Sending...' : 'Sign up with Magic Link'}
        </Button>
      </form>
    </Form>
  );
}

function ProviderForm({ next }: { next?: string }) {
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: executeProvider, status: providerStatus } = useAction(signInWithProviderAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Requesting login...');
    },
    onSuccess: ({ data }) => {
      toast.success('Redirecting...', { id: toastRef.current });
      toastRef.current = undefined;
      if (data?.url) {
        window.location.href = data.url;
      }
    },
    onError: ({ error }) => {
      const errorMessage = getSafeActionErrorMessage(error, 'Failed to login');
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });
  return <RenderProviders
    providers={['google', 'github', 'twitter']}
    isLoading={providerStatus === 'executing'}
    onProviderLoginRequested={(provider: Extract<AuthProvider, 'google' | 'github' | 'twitter'>) => executeProvider({ provider, next })}
  />
}

export function SignUp({ next, nextActionType }: SignUpProps) {
  const [successMessage, setSuccessMessage] = useState<string | null>(null);


  return (
    <div
      data-success={successMessage}
      className="container data-[success]:flex items-center data-[success]:justify-center text-left max-w-lg mx-auto overflow-auto data-[success]:h-full min-h-[470px]"
    >
      {successMessage ? (
        <EmailConfirmationPendingCard
          type="sign-up"
          heading="Confirmation Link Sent"
          message={successMessage}
          resetSuccessMessage={setSuccessMessage}

        />
      ) : (
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
                  <CardTitle>Register to NextBase</CardTitle>
                  <CardDescription>
                    Create an account with your email and password
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-2 p-0">
                  <EmailPasswordForm next={next} setSuccessMessage={setSuccessMessage} />
                </CardContent>
              </Card>
            </TabsContent>
            <TabsContent value="magic-link">
              <Card className="border-none shadow-none">
                <CardHeader className="py-6 px-0">
                  <CardTitle>Register to NextBase</CardTitle>
                  <CardDescription>
                    Create an account with magic link we will send to your email
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-2 p-0">
                  <EmailForm next={next} setSuccessMessage={setSuccessMessage} />
                </CardContent>
              </Card>
            </TabsContent>
            <TabsContent value="social-login">
              <Card className="border-none shadow-none">
                <CardHeader className="py-6 px-0">
                  <CardTitle>Register to NextBase</CardTitle>
                  <CardDescription>
                    Register with your social account
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-2 p-0">
                  <ProviderForm next={next} />
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </div>
      )}
    </div>
  );
}
