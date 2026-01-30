"use client";
import { useMemo, useState } from "react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { T } from "@/components/ui/typography-ui";

export const Email = ({
  onSubmit,
  view,
  isLoading,
  successMessage,
  label = "Email address",
  defaultValue,
  className,
  style,
}: {
  onSubmit: (email: string) => void;
  view: "sign-in" | "sign-up" | "update-email" | "forgot-password";
  isLoading: boolean;
  successMessage?: string | null | undefined;
  label?: string;
  defaultValue?: string;
  className?: string;
  style?: React.CSSProperties;
}) => {
  const [email, setEmail] = useState<string>(defaultValue ?? "");

  const buttonLabelText = useMemo(() => {
    switch (view) {
      case "sign-in":
        return "Login with Magic Link";
      case "sign-up":
        return "Sign up with Magic Link";
      case "update-email":
        return "Update Email";
      case "forgot-password":
        return "Reset password";
    }
  }, [view]);

  return (
    <form
      className={className}
      data-testid="magic-link-form"
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit(email);
      }}
      style={style}
    >
      <div className="space-y-2">
        <div className="space-y-2">
          <Label className="text-muted-foreground" htmlFor="email">
            {label}
          </Label>
          <div>
            <Input
              autoComplete={"email"}
              disabled={isLoading}
              id={`${view}-email`}
              name="email"
              onChange={(event) => setEmail(event.target.value)}
              placeholder="placeholder@email.com"
              required
              type="email"
              value={email}
            />
          </div>
        </div>
        <div className="flex items-center justify-between">
          {view === "forgot-password" ? (
            <div className="text-sm">
              <Link
                className="font-medium text-blue-600 hover:text-blue-500 dark:text-blue-400"
                href="/login"
              >
                Log in instead?
              </Link>
            </div>
          ) : null}
        </div>
        <div>
          <Button className="w-full" type="submit">
            {buttonLabelText}
          </Button>
        </div>
        <div>
          {successMessage ? (
            <T.P className="text-center text-green-500 dark:text-green-400">
              {successMessage}
            </T.P>
          ) : null}
        </div>
      </div>
    </form>
  );
};
