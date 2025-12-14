"use client";
import { ArrowLeft, Check, Fingerprint, Mail } from "lucide-react";
import Link from "next/link";
import type React from "react";

interface IConfirmationPendingCardProps {
  message: string;
  heading: string;
  type: "login" | "sign-up" | "reset-password";
  resetSuccessMessage: React.Dispatch<React.SetStateAction<string | null>>;
  resendEmail?: () => void;
}

export function EmailConfirmationPendingCard({
  message,
  heading,
  type,
  resetSuccessMessage,
  resendEmail,
}: IConfirmationPendingCardProps) {
  const backPath =
    type === "login" ? "/login" : type === "sign-up" ? "/sign-up" : "/login";
  const backLabel = type === "sign-up" ? "Back to sign up" : "Back to login";

  return (
    <div
      className="fade-in-0 slide-in-from-bottom-4 animate-in space-y-6 text-center duration-500"
      data-testid="email-confirmation-pending-card"
    >
      {/* Logo */}
      <Link className="mb-4 inline-flex items-center gap-2" href="/">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary">
          <span className="font-bold text-primary-foreground text-sm">N</span>
        </div>
        <span className="font-semibold text-foreground text-lg">Nextbase</span>
      </Link>

      {/* Success Icon */}
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-primary/10">
        <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary">
          <Check className="h-5 w-5 text-primary-foreground" />
        </div>
      </div>

      {/* Message */}
      <div className="space-y-2">
        <h1 className="font-semibold text-2xl text-foreground tracking-tight">
          {heading}
        </h1>
        <p className="mx-auto max-w-xs text-muted-foreground text-sm">
          {message}
        </p>
      </div>

      {/* Instruction Card */}
      <div className="space-y-3 rounded-xl border border-border/50 bg-muted/50 p-4 text-left">
        <div className="flex items-start gap-3">
          <div className="mt-0.5 flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full border border-border bg-background">
            <Mail className="h-3 w-3 text-muted-foreground" />
          </div>
          <div className="space-y-1">
            <p className="font-medium text-foreground text-sm">
              Check your inbox
            </p>
            <p className="text-muted-foreground text-xs">
              Click the link in the email to{" "}
              {type === "reset-password" ? "reset your password" : "continue"}
            </p>
          </div>
        </div>
        <div className="flex items-start gap-3">
          <div className="mt-0.5 flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full border border-border bg-background">
            {type === "reset-password" ? (
              <Fingerprint className="h-3 w-3 text-muted-foreground" />
            ) : (
              <span className="font-medium text-muted-foreground text-xs">
                !
              </span>
            )}
          </div>
          <div className="space-y-1">
            <p className="font-medium text-foreground text-sm">
              Didn't receive it?
            </p>
            <p className="text-muted-foreground text-xs">
              Check your spam folder or{" "}
              {resendEmail ? (
                <button
                  className="text-foreground underline underline-offset-2 hover:no-underline"
                  onClick={resendEmail}
                  type="button"
                >
                  try again
                </button>
              ) : (
                <button
                  className="text-foreground underline underline-offset-2 hover:no-underline"
                  onClick={() => resetSuccessMessage(null)}
                  type="button"
                >
                  try again
                </button>
              )}
            </p>
          </div>
        </div>
      </div>

      {/* Back Link */}
      <Link
        className="inline-flex items-center gap-2 text-muted-foreground text-sm transition-colors hover:text-foreground"
        href={backPath}
        onClick={() => resetSuccessMessage(null)}
      >
        <ArrowLeft className="h-4 w-4" />
        {backLabel}
      </Link>
    </div>
  );
}
