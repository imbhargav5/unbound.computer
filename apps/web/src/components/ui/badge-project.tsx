import { cva, type VariantProps } from "class-variance-authority";
import type * as React from "react";

import { cn } from "@/utils/cn";
import { Badge } from "./badge";

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-4 py-0.5 font-semibold text-xs uppercase transition-colors focus:outline-hidden focus:ring-2 focus:ring-ring focus:ring-offset-2",

  {
    variants: {
      variant: {
        draft:
          "border-2 border-muted bg-transparent text-muted-foreground hover:bg-muted/80",
        pending_approval: "border-2 border-purple-500 text-purple-500",
        approved: "border-2 border-blue-500 text-blue-500",
        completed: "border-2 border-green-500 text-green-500",
      },
      size: {
        default: "px-4 py-0.5",
        sm: "h-8 rounded-lg",
        lg: "h-11 rounded-md",
      },
    },
    defaultVariants: {
      variant: "draft",
      size: "default",
    },
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {}

function ProjectBadge({ className, variant, ...props }: BadgeProps) {
  const badgeVariant =
    variant === "approved"
      ? "secondary"
      : variant === "pending_approval"
        ? "outline"
        : variant === "completed"
          ? "default"
          : "outline";
  return (
    <Badge className={cn(className, "capitalize")} variant={badgeVariant}>
      {props.children}
    </Badge>
  );
}

export { ProjectBadge, badgeVariants };
