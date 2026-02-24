"use client";

import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { ArrowRight, Mail, Terminal } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { EmailConfirmationPendingCard } from "@/components/authentication/email-confirmation-pending-card";
import * as SocialIcons from "@/components/authentication/icons-list";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import {
  signInWithMagicLinkAction,
  signInWithProviderAction,
} from "@/data/auth/auth";
import { cn } from "@/lib/utils";
import { zodResolver } from "@/lib/zod-resolver";
import { getSafeActionErrorMessage } from "@/utils/error-message";
import {
  signInWithMagicLinkFormSchema,
  type signInWithMagicLinkFormSchemaType,
  type signInWithMagicLinkSchema,
} from "@/utils/zod-schemas/auth";

export function Login({ next }: { next?: string; nextActionType?: string }) {
  const [emailSentSuccessMessage, setEmailSentSuccessMessage] = useState<
    string | null
  >(null);
  const [focusedField, setFocusedField] = useState<string | null>(null);
  const toastRef = useRef<string | number | undefined>(undefined);

  // OAuth Providers
  const { execute: executeProvider, status: providerStatus } = useAction(
    signInWithProviderAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Connecting...");
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
        toast.error("Failed to connect", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    }
  );

  // Magic Link
  const magicLinkMutation = useAction(signInWithMagicLinkAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Sending magic link...");
    },
    onSuccess: () => {
      toast.success("Check your email for the magic link!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
      setEmailSentSuccessMessage(
        "We sent you a magic link. Click it to sign in."
      );
    },
    onError: ({ error }) => {
      const errorMessage = getSafeActionErrorMessage(
        error,
        "Failed to send magic link"
      );
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof signInWithMagicLinkSchema
  >(magicLinkMutation.result.validationErrors, { joinBy: "\n" });

  const form = useForm<signInWithMagicLinkFormSchemaType>({
    resolver: zodResolver(signInWithMagicLinkFormSchema),
    defaultValues: {
      email: "",
      shouldCreateUser: true,
      next,
    },
    errors: hookFormValidationErrors,
  });

  const onSubmit = (data: signInWithMagicLinkFormSchemaType) => {
    magicLinkMutation.execute(data);
  };

  const isLoading =
    providerStatus === "executing" || magicLinkMutation.status === "executing";

  if (emailSentSuccessMessage) {
    return (
      <EmailConfirmationPendingCard
        heading="Check your email"
        message={emailSentSuccessMessage}
        resetSuccessMessage={setEmailSentSuccessMessage}
        type="login"
      />
    );
  }

  return (
    <div className="fade-in-0 slide-in-from-bottom-4 animate-in space-y-8 duration-500">
      {/* Logo */}
      <Link className="inline-flex items-center gap-2" href="/">
        <div className="flex size-8 items-center justify-center rounded-lg border border-white/20">
          <Terminal className="size-4 text-white" />
        </div>
        <span className="font-medium text-lg text-white">Unbound</span>
      </Link>

      {/* Header */}
      <div className="space-y-2">
        <h1 className="font-light text-3xl text-white tracking-tight">
          Welcome back
        </h1>
        <p className="text-white/50">Sign in to access your account</p>
      </div>

      {/* OAuth Providers */}
      <div className="space-y-3">
        <Button
          className="h-12 w-full gap-3 bg-white font-medium text-black hover:bg-white/90"
          disabled={isLoading}
          onClick={() => executeProvider({ provider: "github", next })}
        >
          <SocialIcons.github />
          Continue with GitHub
        </Button>
        <Button
          className="h-12 w-full gap-3 border border-white/10 bg-transparent font-medium text-white hover:bg-white/5"
          disabled={isLoading}
          onClick={() => executeProvider({ provider: "google", next })}
          variant="outline"
        >
          <SocialIcons.google />
          Continue with Google
        </Button>
      </div>

      {/* Divider */}
      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-white/10 border-t" />
        </div>
        <div className="relative flex justify-center text-xs">
          <span className="bg-black px-4 text-white/40">or</span>
        </div>
      </div>

      {/* Magic Link Form */}
      <Form {...form}>
        <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)}>
          <FormField
            control={form.control}
            name="email"
            render={({ field }) => (
              <FormItem>
                <div className="relative">
                  <Mail
                    className={cn(
                      "absolute top-1/2 left-3 size-4 -translate-y-1/2 transition-colors duration-200",
                      focusedField === "email" ? "text-white" : "text-white/40"
                    )}
                  />
                  <FormControl>
                    <Input
                      {...field}
                      autoComplete="email"
                      className="h-12 border-white/10 bg-white/[0.02] pl-10 text-white placeholder:text-white/30 focus:border-white/20 focus:ring-0"
                      disabled={isLoading}
                      onBlur={() => setFocusedField(null)}
                      onFocus={() => setFocusedField("email")}
                      placeholder="name@example.com"
                      type="email"
                    />
                  </FormControl>
                </div>
                <FormMessage />
              </FormItem>
            )}
          />

          <Button
            className="h-12 w-full gap-2 border border-white/10 bg-transparent font-medium text-white hover:bg-white/5"
            disabled={isLoading}
            type="submit"
            variant="outline"
          >
            {magicLinkMutation.status === "executing" ? (
              "Sending..."
            ) : (
              <>
                Continue with Email
                <ArrowRight className="size-4" />
              </>
            )}
          </Button>
        </form>
      </Form>

      {/* Footer */}
      <p className="text-center text-sm text-white/40">
        Don't have an account?{" "}
        <Link
          className="text-white transition-colors hover:text-white/80"
          href="/sign-up"
        >
          Sign up
        </Link>
      </p>
    </div>
  );
}
