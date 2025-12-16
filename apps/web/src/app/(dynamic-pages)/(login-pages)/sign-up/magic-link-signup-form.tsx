"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { ArrowRight, Mail } from "lucide-react";
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
import { signInWithMagicLinkAction } from "@/data/auth/auth";
import { cn } from "@/lib/utils";
import { getSafeActionErrorMessage } from "@/utils/error-message";
import {
  signInWithMagicLinkFormSchema,
  type signInWithMagicLinkFormSchemaType,
  type signInWithMagicLinkSchema,
} from "@/utils/zod-schemas/auth";

interface MagicLinkSignupFormProps {
  next?: string;
  setSuccessMessage: (message: string) => void;
}

export function MagicLinkSignupForm({
  next,
  setSuccessMessage,
}: MagicLinkSignupFormProps) {
  const toastRef = useRef<string | number | undefined>(undefined);
  const [focusedField, setFocusedField] = useState<string | null>(null);

  const signInWithMagicLinkMutation = useAction(signInWithMagicLinkAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Sending magic link...");
    },
    onSuccess: () => {
      toast.success("A magic link has been sent to your email!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
      setSuccessMessage("A magic link has been sent to your email!");
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
  >(signInWithMagicLinkMutation.result.validationErrors, { joinBy: "\n" });

  const { execute: executeMagicLink, status: magicLinkStatus } =
    signInWithMagicLinkMutation;

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
    executeMagicLink(data);
  };

  const isLoading = magicLinkStatus === "executing";

  return (
    <Form {...form}>
      <form
        className="space-y-4"
        data-testid="magic-link-form"
        onSubmit={form.handleSubmit(onSubmit)}
      >
        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem className="space-y-2">
              <Label
                className="font-medium text-foreground text-sm"
                htmlFor="sign-up-email"
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
                    id="sign-up-email"
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
          disabled={isLoading}
          type="submit"
        >
          {isLoading ? (
            "Sending..."
          ) : (
            <span className="flex items-center gap-2">
              Sign up with Magic Link
              <ArrowRight className="h-4 w-4" />
            </span>
          )}
        </Button>
      </form>
    </Form>
  );
}
