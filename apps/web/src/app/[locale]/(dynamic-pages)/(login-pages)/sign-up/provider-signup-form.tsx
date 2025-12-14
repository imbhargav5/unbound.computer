"use client";

import { useAction } from "next-cool-action/hooks";
import { useRef } from "react";
import { toast } from "sonner";

import { RenderProviders } from "@/components/authentication/render-providers";
import { signInWithProviderAction } from "@/data/auth/auth";
import type { AuthProvider } from "@/types";
import { getSafeActionErrorMessage } from "@/utils/error-message";

interface ProviderSignupFormProps {
  next?: string;
}

export function ProviderSignupForm({ next }: ProviderSignupFormProps) {
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: executeProvider, status: providerStatus } = useAction(
    signInWithProviderAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Requesting login...");
      },
      onSuccess: ({ data }) => {
        toast.success("Redirecting...", { id: toastRef.current });
        toastRef.current = undefined;
        if (data?.url) {
          window.location.href = data.url;
        }
      },
      onError: ({ error }) => {
        const errorMessage = getSafeActionErrorMessage(
          error,
          "Failed to login"
        );
        toast.error(errorMessage, { id: toastRef.current });
        toastRef.current = undefined;
      },
    }
  );

  return (
    <RenderProviders
      isLoading={providerStatus === "executing"}
      onProviderLoginRequested={(
        provider: Extract<AuthProvider, "google" | "github" | "twitter">
      ) => executeProvider({ provider, next })}
      providers={["google", "github", "twitter"]}
    />
  );
}
