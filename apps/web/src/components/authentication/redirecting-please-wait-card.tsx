"use client";
import { Loader2 } from "lucide-react";
import Link from "next/link";

interface RedirectingPleaseWaitCardProps {
  message: string;
  heading: string;
}

export function RedirectingPleaseWaitCard({
  message,
  heading,
}: RedirectingPleaseWaitCardProps) {
  return (
    <div className="fade-in-0 slide-in-from-bottom-4 animate-in space-y-6 text-center duration-500">
      {/* Logo */}
      <Link className="mb-4 inline-flex items-center gap-2" href="/">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary">
          <span className="font-bold text-primary-foreground text-sm">N</span>
        </div>
        <span className="font-semibold text-foreground text-lg">Outbound</span>
      </Link>

      {/* Loading Icon */}
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-primary/10">
        <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary">
          <Loader2 className="h-5 w-5 animate-spin text-primary-foreground" />
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
    </div>
  );
}
