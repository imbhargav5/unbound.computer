'use client';

import { EmailConfirmationPendingCard } from '@/components/Auth/EmailConfirmationPendingCard';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useState } from 'react';
import { MagicLinkSignupForm } from './MagicLinkSignupForm';
import { PasswordSignupForm } from './PasswordSignupForm';
import { ProviderSignupForm } from './ProviderSignupForm';

interface SignUpProps {
  next?: string;
  nextActionType?: string;
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
                  <PasswordSignupForm next={next} setSuccessMessage={setSuccessMessage} />
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
                  <MagicLinkSignupForm next={next} setSuccessMessage={setSuccessMessage} />
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
                  <ProviderSignupForm next={next} />
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </div>
      )}
    </div>
  );
}
