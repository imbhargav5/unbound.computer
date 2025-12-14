"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { ArrowLeft, ArrowRight, Mail } from "lucide-react";
import Link from "next/link";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { EmailConfirmationPendingCard } from "@/components/authentication/email-confirmation-pending-card";
import { Button } from "@/components/ui/button";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { resetPasswordAction } from "@/data/auth/auth";
import { cn } from "@/lib/utils";
import { getSafeActionErrorMessage } from "@/utils/error-message";
import {
  type ResetPasswordSchemaType,
  resetPasswordSchema,
} from "@/utils/zod-schemas/auth";

export function ForgotPassword() {
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [focusedField, setFocusedField] = useState<string | null>(null);
  const toastRef = useRef<string | number | undefined>(undefined);

  const resetPasswordMutation = useAction(resetPasswordAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Sending password reset link...");
    },
    onSuccess: () => {
      toast.success("Password reset link sent!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
      setSuccessMessage("A password reset link has been sent to your email!");
    },
    onError: ({ error }) => {
      const errorMessage = getSafeActionErrorMessage(
        error,
        "Failed to send password reset link"
      );
      toast.error(errorMessage, {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
  });

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof resetPasswordSchema
  >(resetPasswordMutation.result.validationErrors, { joinBy: "\n" });

  const { execute, status } = resetPasswordMutation;

  const form = useForm<ResetPasswordSchemaType>({
    resolver: zodResolver(resetPasswordSchema),
    defaultValues: {
      email: "",
    },
    errors: hookFormValidationErrors,
  });

  const onSubmit = (data: ResetPasswordSchemaType) => {
    execute(data);
  };

  if (successMessage) {
    return (
      <EmailConfirmationPendingCard
        heading="Reset password link sent"
        message={successMessage}
        resetSuccessMessage={setSuccessMessage}
        type="reset-password"
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
          Reset password
        </h1>
        <p className="text-muted-foreground text-sm">
          We'll send you a link to reset your password
        </p>
      </div>

      {/* Form */}
      <Form {...form}>
        <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)}>
          <FormField
            control={form.control}
            name="email"
            render={({ field }) => (
              <FormItem className="space-y-2">
                <Label
                  className="font-medium text-foreground text-sm"
                  htmlFor="email"
                >
                  Email
                </Label>
                <div className="relative">
                  <Mail
                    className={cn(
                      "-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 transition-colors duration-200",
                      focusedField === "email"
                        ? "text-foreground"
                        : "text-muted-foreground"
                    )}
                  />
                  <FormControl>
                    <Input
                      {...field}
                      className="h-11 border-input bg-background pl-10 transition-all duration-200 focus:ring-2 focus:ring-ring/20"
                      disabled={status === "executing"}
                      id="email"
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
            className="h-11 w-full font-medium transition-all duration-200"
            disabled={status === "executing"}
            type="submit"
          >
            {status === "executing" ? (
              "Sending..."
            ) : (
              <span className="flex items-center gap-2">
                Send reset link
                <ArrowRight className="h-4 w-4" />
              </span>
            )}
          </Button>
        </form>
      </Form>

      {/* Back to login */}
      <Link
        className="inline-flex items-center gap-2 text-muted-foreground text-sm transition-colors hover:text-foreground"
        href="/login"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to login
      </Link>
    </div>
  );
}
