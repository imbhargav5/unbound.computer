"use client";

import { ArrowRight, Lock } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { updatePasswordAction } from "@/data/user/security";
import { cn } from "@/lib/utils";
import { getSafeActionErrorMessage } from "@/utils/error-message";

export function UpdatePassword() {
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);
  const [password, setPassword] = useState("");
  const [focusedField, setFocusedField] = useState<string | null>(null);

  const { execute, status } = useAction(updatePasswordAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating password...");
    },
    onSuccess: () => {
      toast.success("Password updated!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
      router.push("/auth/callback");
    },
    onError: ({ error }) => {
      const errorMessage = getSafeActionErrorMessage(
        error,
        "Failed to update password"
      );
      toast.error(errorMessage, {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
  });

  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    execute({ password });
  };

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
        <h1
          className="font-semibold text-2xl text-foreground tracking-tight"
          data-testid="update-password-title"
        >
          Create new password
        </h1>
        <p className="text-muted-foreground text-sm">
          Enter your new password below
        </p>
      </div>

      {/* Form */}
      <form
        className="space-y-4"
        data-testid="password-form"
        onSubmit={handleSubmit}
      >
        <div className="space-y-2">
          <Label
            className="font-medium text-foreground text-sm"
            htmlFor="password"
          >
            New Password
          </Label>
          <div className="relative">
            <Lock
              className={cn(
                "-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 transition-colors duration-200",
                focusedField === "password"
                  ? "text-foreground"
                  : "text-muted-foreground"
              )}
            />
            <Input
              className="h-11 border-input bg-background pl-10 transition-all duration-200 focus:ring-2 focus:ring-ring/20"
              disabled={status === "executing"}
              id="password"
              onBlur={() => setFocusedField(null)}
              onChange={(e) => setPassword(e.target.value)}
              onFocus={() => setFocusedField("password")}
              placeholder="Enter your new password"
              required
              type="password"
              value={password}
            />
          </div>
        </div>

        <Button
          className="h-11 w-full font-medium transition-all duration-200"
          disabled={status === "executing"}
          type="submit"
        >
          {status === "executing" ? (
            "Updating..."
          ) : (
            <span className="flex items-center gap-2">
              Update password
              <ArrowRight className="h-4 w-4" />
            </span>
          )}
        </Button>
      </form>
    </div>
  );
}
