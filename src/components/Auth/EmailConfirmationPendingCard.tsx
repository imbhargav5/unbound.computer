"use client";
import { ArrowLeftIcon, Fingerprint, MailIcon } from "lucide-react";

import type React from "react";

import { useRouter } from "next/navigation";
import { Button } from "../ui/button";
import {
  Card,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "../ui/card";

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
  const router = useRouter();
  return (
    <div
      data-testid="email-confirmation-pending-card"
      className="w-full max-w-md mx-auto px-4"
    >
      <Card className="border shadow-md overflow-hidden p-1 min-w-[320px] w-full">
        <CardHeader className="space-y-4 pt-8 pb-6">
          <div className="rounded-full bg-muted/30 p-3 w-fit mx-auto">
            {type === "reset-password" ? (
              <Fingerprint className="w-8 h-8" />
            ) : (
              <MailIcon className="w-8 h-8" />
            )}
          </div>
          <div className="space-y-1.5">
            <CardTitle className="text-center text-xl font-semibold">
              {heading}
            </CardTitle>
            <CardDescription className="text-center max-w-xs mx-auto">
              {message}
            </CardDescription>
          </div>
        </CardHeader>
        <CardFooter className="flex flex-col gap-4 pb-8">
          <Button
            variant="secondary"
            className="w-full max-w-xs mx-auto"
            onClick={() => {
              resetSuccessMessage(null);
              router.push(
                type === "login"
                  ? "/login"
                  : type === "sign-up"
                    ? "/sign-up"
                    : "/login",
              );
            }}
          >
            <ArrowLeftIcon className="w-4 h-4 mr-2" />
            {type === "sign-up" ? "Back to sign up" : "Back to login"}
          </Button>
        </CardFooter>
      </Card>
      {type === "sign-up" && resendEmail && (
        <div className="text-center mt-6">
          <p className="text-sm text-muted-foreground">
            Didn&apos;t receive the email?{" "}
            <Button
              className="font-medium underline underline-offset-4 hover:text-primary px-0"
              variant="link"
              onClick={resendEmail}
            >
              Click to resend
            </Button>
          </p>
        </div>
      )}
    </div>
  );
}
