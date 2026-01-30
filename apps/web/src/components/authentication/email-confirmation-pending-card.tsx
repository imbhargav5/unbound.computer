"use client";
import { ArrowLeft, Check, Fingerprint, Mail, Terminal } from "lucide-react";
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
        <div className="flex size-8 items-center justify-center rounded-lg border border-white/20">
          <Terminal className="size-4 text-white" />
        </div>
        <span className="font-medium text-lg text-white">Unbound</span>
      </Link>

      {/* Success Icon */}
      <div className="mx-auto flex size-16 items-center justify-center rounded-full border border-white/20 bg-white/[0.02]">
        <div className="flex size-10 items-center justify-center rounded-full bg-white">
          <Check className="size-5 text-black" />
        </div>
      </div>

      {/* Message */}
      <div className="space-y-2">
        <h1 className="font-light text-2xl text-white tracking-tight">
          {heading}
        </h1>
        <p className="mx-auto max-w-xs text-sm text-white/50">{message}</p>
      </div>

      {/* Instruction Card */}
      <div className="space-y-3 rounded-xl border border-white/10 bg-white/[0.02] p-4 text-left">
        <div className="flex items-start gap-3">
          <div className="mt-0.5 flex size-6 flex-shrink-0 items-center justify-center rounded-full border border-white/20">
            <Mail className="size-3 text-white/50" />
          </div>
          <div className="space-y-1">
            <p className="font-medium text-sm text-white">Check your inbox</p>
            <p className="text-white/40 text-xs">
              Click the link in the email to{" "}
              {type === "reset-password" ? "reset your password" : "continue"}
            </p>
          </div>
        </div>
        <div className="flex items-start gap-3">
          <div className="mt-0.5 flex size-6 flex-shrink-0 items-center justify-center rounded-full border border-white/20">
            {type === "reset-password" ? (
              <Fingerprint className="size-3 text-white/50" />
            ) : (
              <span className="font-medium text-white/50 text-xs">!</span>
            )}
          </div>
          <div className="space-y-1">
            <p className="font-medium text-sm text-white">Didn't receive it?</p>
            <p className="text-white/40 text-xs">
              Check your spam folder or{" "}
              {resendEmail ? (
                <button
                  className="text-white underline underline-offset-2 hover:no-underline"
                  onClick={resendEmail}
                  type="button"
                >
                  try again
                </button>
              ) : (
                <button
                  className="text-white underline underline-offset-2 hover:no-underline"
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
        className="inline-flex items-center gap-2 text-sm text-white/50 transition-colors hover:text-white"
        href={backPath}
        onClick={() => resetSuccessMessage(null)}
      >
        <ArrowLeft className="size-4" />
        {backLabel}
      </Link>
    </div>
  );
}
