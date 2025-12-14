"use client";

import { useState } from "react";
import { EmailConfirmationPendingCard } from "@/components/authentication/email-confirmation-pending-card";
import { Link } from "@/components/intl-link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { MagicLinkSignupForm } from "./magic-link-signup-form";
import { PasswordSignupForm } from "./password-signup-form";
import { ProviderSignupForm } from "./provider-signup-form";

interface SignUpProps {
  next?: string;
  nextActionType?: string;
}

export function SignUp({ next, nextActionType }: SignUpProps) {
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  if (successMessage) {
    return (
      <EmailConfirmationPendingCard
        heading="Confirmation Link Sent"
        message={successMessage}
        resetSuccessMessage={setSuccessMessage}
        type="sign-up"
      />
    );
  }

  return (
    <div className="fade-in-0 slide-in-from-bottom-4 animate-in space-y-6 duration-500">
      {/* Logo */}
      <Link className="mb-2 inline-flex items-center gap-2" href="/">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary">
          <span className="font-bold text-primary-foreground text-sm">N</span>
        </div>
        <span className="font-semibold text-foreground text-lg">Nextbase</span>
      </Link>

      {/* Header */}
      <div className="space-y-2">
        <h1 className="font-semibold text-2xl text-foreground tracking-tight">
          Create your Account
        </h1>
        <p className="text-muted-foreground text-sm">
          Choose your preferred signup method
        </p>
      </div>

      {/* Tabs */}
      <Tabs className="w-full" defaultValue="password">
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="password">Password</TabsTrigger>
          <TabsTrigger value="magic-link">Magic Link</TabsTrigger>
        </TabsList>
        <TabsContent value="password">
          <PasswordSignupForm
            next={next}
            setSuccessMessage={setSuccessMessage}
          />
        </TabsContent>
        <TabsContent value="magic-link">
          <MagicLinkSignupForm
            next={next}
            setSuccessMessage={setSuccessMessage}
          />
        </TabsContent>
      </Tabs>

      {/* Divider */}
      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-border border-t" />
        </div>
        <div className="relative flex justify-center text-xs">
          <span className="bg-background px-3 text-muted-foreground">
            or continue with
          </span>
        </div>
      </div>

      {/* OAuth Providers */}
      <ProviderSignupForm next={next} />

      {/* Footer Link */}
      <p className="text-center text-muted-foreground text-sm">
        Already have an account?{" "}
        <Link
          className="font-medium text-foreground underline-offset-4 hover:underline"
          href="/login"
        >
          Sign in
        </Link>
      </p>
    </div>
  );
}
