import { type ComponentProps, useState } from "react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { classNames } from "@/utils/class-names";

export const EmailAndPassword = ({
  onSubmit,
  view,
  isLoading,
}: {
  onSubmit: (data: { email: string; password: string }) => void;
  view: "sign-in" | "sign-up";
  isLoading: boolean;
} & ComponentProps<typeof Button>) => {
  const [email, setEmail] = useState<string>("");
  const [password, setPassword] = useState<string>("");

  return (
    <form
      data-testid="password-form"
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit({
          email,
          password,
        });
      }}
    >
      <div className="space-y-4">
        <div>
          <Label className="text-foreground" htmlFor="email">
            Email address
          </Label>
          <div className="mt-1">
            <input
              autoComplete={"email"}
              className="block h-10 w-full appearance-none rounded-md border bg-gray-50/10 px-3 py-3 placeholder-muted-foreground shadow-xs focus:border-blue-500 focus:outline-hidden focus:ring-blue-500 sm:text-sm dark:bg-gray-800/20"
              data-strategy="email-password"
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
        <div className="space-y-1">
          <Label className="text-foreground" htmlFor="password">
            Password
          </Label>
          <div className="mt-1">
            <input
              autoComplete={
                view === "sign-in" ? "current-password" : "new-password"
              }
              className="block h-10 w-full appearance-none rounded-md border bg-gray-50/10 px-3 py-3 placeholder-muted-foreground shadow-xs focus:border-blue-500 focus:outline-hidden focus:ring-blue-500 sm:text-sm dark:bg-gray-800/20"
              disabled={isLoading}
              id={`${view}-password`}
              name="password"
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Type your password"
              required
              type="password"
              value={password}
            />
          </div>
        </div>

        <div className="flex items-center justify-between">
          {view === "sign-in" ? (
            <div className="text-sm">
              <Link
                className="font-medium text-muted-foreground hover:text-foreground dark:hover:text-gray-600"
                href="/forgot-password"
              >
                Forgot your password?
              </Link>
            </div>
          ) : null}
        </div>
        <div className="space-y-2">
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
              {view === "sign-in" ? "Login" : "Sign up"}
            </Button>
          )}
          <div className="w-full text-center">
            {view === "sign-in" ? (
              <div className="text-sm">
                <Link
                  className="font-medium text-muted-foreground hover:text-foreground"
                  href="/sign-up"
                >
                  Don&apos;t have an account? Sign up
                </Link>
              </div>
            ) : (
              <div className="text-sm">
                <Link
                  className="font-medium text-muted-foreground hover:text-foreground"
                  href="/login"
                >
                  Already have an account? Log in
                </Link>
              </div>
            )}
          </div>
        </div>
      </div>
    </form>
  );
};
