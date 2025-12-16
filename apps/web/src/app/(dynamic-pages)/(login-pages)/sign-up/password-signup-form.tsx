"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { ArrowRight, Lock, Mail } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
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
import { signUpWithPasswordAction } from "@/data/auth/auth";
import { cn } from "@/lib/utils";
import { getSafeActionErrorMessage } from "@/utils/error-message";
import {
  type SignUpWithPasswordSchemaType,
  signUpWithPasswordSchema,
} from "@/utils/zod-schemas/auth";

interface PasswordSignupFormProps {
  next?: string;
  setSuccessMessage: (message: string) => void;
}

export function PasswordSignupForm({
  next,
  setSuccessMessage,
}: PasswordSignupFormProps) {
  const toastRef = useRef<string | number | undefined>(undefined);
  const [focusedField, setFocusedField] = useState<string | null>(null);

  const signUpWithPasswordMutation = useAction(signUpWithPasswordAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Creating account...");
    },
    onSuccess: () => {
      toast.success("Account created!", { id: toastRef.current });
      toastRef.current = undefined;
      setSuccessMessage("A confirmation link has been sent to your email!");
    },
    onError: ({ error }) => {
      const errorMessage = getSafeActionErrorMessage(
        error,
        "Failed to create account"
      );
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof signUpWithPasswordSchema
  >(signUpWithPasswordMutation.result.validationErrors, { joinBy: "\n" });

  const { execute: executeSignUp, status: signUpStatus } =
    signUpWithPasswordMutation;

  const form = useForm<SignUpWithPasswordSchemaType>({
    resolver: zodResolver(signUpWithPasswordSchema),
    defaultValues: {
      email: "",
      password: "",
      next,
    },
    errors: hookFormValidationErrors,
  });

  const onSubmit = (data: SignUpWithPasswordSchemaType) => {
    executeSignUp({ ...data, next });
  };

  const isLoading = signUpStatus === "executing";

  return (
    <Form {...form}>
      <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)}>
        {/* Email Field */}
        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem className="space-y-2">
              <Label
                className="font-medium text-foreground text-sm"
                htmlFor="signup-email"
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
                    autoComplete="email"
                    className="h-11 border-input bg-background pl-10 transition-all duration-200 focus:ring-2 focus:ring-ring/20"
                    disabled={isLoading}
                    id="signup-email"
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

        {/* Password Field */}
        <FormField
          control={form.control}
          name="password"
          render={({ field }) => (
            <FormItem className="space-y-2">
              <Label
                className="font-medium text-foreground text-sm"
                htmlFor="signup-password"
              >
                Password
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
                <FormControl>
                  <Input
                    {...field}
                    autoComplete="new-password"
                    className="h-11 border-input bg-background pl-10 transition-all duration-200 focus:ring-2 focus:ring-ring/20"
                    disabled={isLoading}
                    id="signup-password"
                    onBlur={() => setFocusedField(null)}
                    onFocus={() => setFocusedField("password")}
                    placeholder="Create a password"
                    type="password"
                  />
                </FormControl>
              </div>
              <FormMessage />
            </FormItem>
          )}
        />

        <Button
          className="h-11 w-full font-medium transition-all duration-200"
          disabled={isLoading}
          type="submit"
        >
          {isLoading ? (
            "Creating account..."
          ) : (
            <span className="flex items-center gap-2">
              Create account
              <ArrowRight className="h-4 w-4" />
            </span>
          )}
        </Button>
      </form>
    </Form>
  );
}
