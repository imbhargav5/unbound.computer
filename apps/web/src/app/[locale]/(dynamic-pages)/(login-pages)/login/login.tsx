"use client";

import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { EmailConfirmationPendingCard } from "@/components/authentication/email-confirmation-pending-card";
import { RedirectingPleaseWaitCard } from "@/components/authentication/redirecting-please-wait-card";
import { RenderProviders } from "@/components/authentication/render-providers";
import { Link } from "@/components/intl-link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { signInWithProviderAction } from "@/data/auth/auth";
import { useRouter } from "@/i18n/navigation";
import { MagicLinkLoginForm } from "./magic-link-login-form";
import { PasswordLoginForm } from "./password-login-form";

export function Login({
  next,
  nextActionType,
}: {
  next?: string;
  nextActionType?: string;
}) {
  const [emailSentSuccessMessage, setEmailSentSuccessMessage] = useState<
    string | null
  >(null);
  const [redirectInProgress, setRedirectInProgress] = useState(false);
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);

  function redirectToDashboard() {
    if (next) {
      router.push(`/auth/callback?next=${next}`);
    } else {
      router.push("/dashboard");
    }
  }

  const { execute: executeProvider, status: providerStatus } = useAction(
    signInWithProviderAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Requesting login...");
      },
      onSuccess: ({ data }) => {
        if (data) {
          toast.success("Redirecting...", {
            id: toastRef.current,
          });
          toastRef.current = undefined;
          window.location.href = data.url;
        }
      },
      onError: () => {
        toast.error("Failed to login", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    }
  );

  if (emailSentSuccessMessage) {
    return (
      <EmailConfirmationPendingCard
        heading={"Confirmation Link Sent"}
        message={emailSentSuccessMessage}
        resetSuccessMessage={setEmailSentSuccessMessage}
        type={"login"}
      />
    );
  }

  if (redirectInProgress) {
    return (
      <RedirectingPleaseWaitCard
        heading="Redirecting to Dashboard"
        message="Please wait while we redirect you to your dashboard."
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
          Login to Your Account
        </h1>
        <p className="text-muted-foreground text-sm">
          Choose your preferred login method
        </p>
      </div>

      {/* Tabs */}
      <Tabs className="w-full" defaultValue="password">
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="password">Password</TabsTrigger>
          <TabsTrigger value="magic-link">Magic Link</TabsTrigger>
        </TabsList>
        <TabsContent value="password">
          <PasswordLoginForm
            next={next}
            redirectToDashboard={redirectToDashboard}
            setRedirectInProgress={setRedirectInProgress}
          />
        </TabsContent>
        <TabsContent value="magic-link">
          <MagicLinkLoginForm
            next={next}
            setEmailSentSuccessMessage={setEmailSentSuccessMessage}
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
      <RenderProviders
        isLoading={providerStatus === "executing"}
        onProviderLoginRequested={(provider) =>
          executeProvider({ provider, next })
        }
        providers={["google", "github", "twitter"]}
      />

      {/* Footer Links */}
      <div className="flex items-center justify-between text-sm">
        <Link
          className="font-medium text-muted-foreground transition-colors hover:text-foreground hover:underline hover:underline-offset-4"
          href="/forgot-password"
        >
          Forgot password?
        </Link>
        <Link
          className="font-medium text-foreground hover:underline hover:underline-offset-4"
          href="/sign-up"
        >
          Sign up instead
        </Link>
      </div>
    </div>
  );
}
