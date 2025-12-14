"use client";
import { type CSSProperties, useState } from "react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { T } from "@/components/ui/typography-ui";
import { classNames } from "@/utils/class-names";

export const Password = ({
  onSubmit,
  isLoading,
  successMessage,
  label = "Password",
  buttonLabel = "Update",
  className,
  style,
}: {
  onSubmit: (password: string) => void;
  isLoading: boolean;
  successMessage?: string;
  label?: string;
  buttonLabel?: string;
  className?: string;
  style?: CSSProperties;
}) => {
  const [password, setPassword] = useState<string>("");

  return (
    <form
      className={className}
      data-testid="password-form"
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit(password);
      }}
      style={style}
    >
      <div className="space-y-4">
        <div className="space-y-2">
          <Label className="text-muted-foreground" htmlFor="email">
            {label}
          </Label>
          <div>
            <input
              autoComplete="email"
              className="block h-10 w-full appearance-none rounded-md border bg-gray-50/10 px-3 py-3 placeholder-muted-foreground shadow-xs focus:border-blue-500 focus:outline-hidden focus:ring-blue-500 sm:text-sm dark:bg-gray-800/20"
              disabled={isLoading}
              id="password"
              name="password"
              onChange={(event) => setPassword(event.target.value)}
              required
              type="password"
              value={password}
            />
          </div>
        </div>
        <div>
          {isLoading ? (
            <Button
              className={classNames(
                "flex w-full justify-center rounded-lg border border-transparent px-4 py-3 font-medium text-sm text-white shadow-xs focus:outline-hidden focus:ring-2 focus:ring-offset-2 dark:text-black",
                isLoading
                  ? "bg-yellow-300 dark:bg-yellow-700"
                  : "bg-black hover:bg-gray-900 dark:bg-white dark:hover:bg-gray-100"
              )}
              disabled
              type="submit"
            >
              Loading...
            </Button>
          ) : (
            <Button
              className={classNames(
                "flex w-full justify-center rounded-lg border border-transparent px-4 py-2 font-medium text-sm text-white shadow-xs focus:outline-hidden focus:ring-2 focus:ring-offset-2 dark:text-black",
                isLoading
                  ? "bg-yellow-300 dark:bg-yellow-700"
                  : "bg-black hover:bg-gray-900 dark:bg-white dark:hover:bg-gray-100"
              )}
              type="submit"
            >
              {buttonLabel}
            </Button>
          )}
        </div>
        <div>
          {successMessage ? (
            <T.P className="text-center text-green-500 text-sm dark:text-green-400">
              {successMessage}
            </T.P>
          ) : null}
        </div>
      </div>
    </form>
  );
};
