import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function Subtle({ className, ...rest }: ComponentProps<"p">) {
  const classNames = cn("text-muted-foreground text-sm", className);
  return <p className={classNames} {...rest} />;
}
