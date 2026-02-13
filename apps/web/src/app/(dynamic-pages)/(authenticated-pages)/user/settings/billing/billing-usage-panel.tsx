"use client";

import { AlertCircle, AlertTriangle, CheckCircle2, ShieldAlert } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useMemo, useRef } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { createUserCheckoutSession } from "@/data/user/billing";
import { cn } from "@/lib/utils";

export type BillingUsageStatusView = {
  plan: "free" | "paid";
  gateway: string;
  periodStart: string;
  periodEnd: string;
  commandsLimit: number;
  commandsUsed: number;
  commandsRemaining: number;
  enforcementState: "ok" | "near_limit" | "over_quota";
  updatedAt: string;
};

export type BillingUpgradeOption = {
  priceId: string;
  title: string;
  label: string;
};

const enforcementStyles = {
  ok: {
    icon: CheckCircle2,
    title: "Usage in range",
    className: "text-emerald-600",
  },
  near_limit: {
    icon: AlertTriangle,
    title: "Near command limit",
    className: "text-amber-600",
  },
  over_quota: {
    icon: ShieldAlert,
    title: "Command limit reached",
    className: "text-red-600",
  },
} as const;

function formatDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
}

export function BillingUsagePanel({
  usageStatus,
  upgradeOption,
  errorMessage,
}: {
  usageStatus: BillingUsageStatusView | null;
  upgradeOption: BillingUpgradeOption | null;
  errorMessage: string | null;
}) {
  const toastRef = useRef<string | number | undefined>(undefined);
  const { execute: startCheckout, isPending } = useAction(
    createUserCheckoutSession,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Redirecting to checkout...");
      },
      onSuccess: ({ data }) => {
        if (data?.url) {
          window.location.href = data.url;
          return;
        }
        toast.error("Checkout session URL not found.", { id: toastRef.current });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        toast.error(error.serverError ?? "Failed to start checkout.", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    }
  );

  const usageProgress = useMemo(() => {
    if (!usageStatus || usageStatus.commandsLimit <= 0) {
      return 0;
    }
    return Math.min(
      100,
      Math.max(0, (usageStatus.commandsUsed / usageStatus.commandsLimit) * 100)
    );
  }, [usageStatus]);

  const enforcement = usageStatus
    ? enforcementStyles[usageStatus.enforcementState]
    : null;
  const EnforcementIcon = enforcement?.icon ?? AlertCircle;

  const checkoutLabel =
    usageStatus?.plan === "free" || usageStatus?.enforcementState === "over_quota"
      ? "Upgrade Plan"
      : "Change Plan";

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          Billing Snapshot
          {usageStatus ? (
            <Badge variant="secondary">
              {usageStatus.plan.toUpperCase()} • {usageStatus.gateway.toUpperCase()}
            </Badge>
          ) : null}
        </CardTitle>
        <CardDescription>
          Usage status is refreshed in the background and can lag by up to ~5
          minutes.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {usageStatus ? (
          <>
            <div
              className={cn(
                "flex items-center gap-2 font-medium text-sm",
                enforcement?.className
              )}
            >
              <EnforcementIcon className="size-4" />
              <span>{enforcement?.title}</span>
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Command usage</span>
                <span className="font-medium">
                  {usageStatus.commandsUsed}/{usageStatus.commandsLimit}
                </span>
              </div>
              <Progress className="h-2" value={usageProgress} />
              <p className="text-muted-foreground text-xs">
                {usageStatus.commandsRemaining} command(s) remaining in the
                current period.
              </p>
            </div>

            <div className="grid gap-3 text-sm sm:grid-cols-2">
              <div>
                <p className="text-muted-foreground">Period start</p>
                <p>{formatDate(usageStatus.periodStart)}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Period end</p>
                <p>{formatDate(usageStatus.periodEnd)}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Last updated</p>
                <p>{formatDate(usageStatus.updatedAt)}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Enforcement state</p>
                <p className="font-medium">{usageStatus.enforcementState}</p>
              </div>
            </div>
          </>
        ) : (
          <div className="rounded-md border border-dashed p-4 text-sm">
            <p className="font-medium">Billing usage unavailable</p>
            <p className="mt-1 text-muted-foreground">
              {errorMessage ??
                "We could not load a usage snapshot for your account right now."}
            </p>
          </div>
        )}

        <div className="space-y-2 rounded-md border bg-muted/30 p-4">
          <p className="font-medium text-sm">Upgrade or update plan</p>
          <p className="text-muted-foreground text-sm">
            {upgradeOption
              ? `${upgradeOption.title} (${upgradeOption.label})`
              : "No active recurring Stripe plan is currently available."}
          </p>
          <Button
            disabled={isPending || !upgradeOption}
            onClick={() =>
              upgradeOption
                ? startCheckout({ priceId: upgradeOption.priceId })
                : undefined
            }
          >
            {isPending ? "Redirecting..." : checkoutLabel}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
