import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function Large({ className, ...rest }: ComponentProps<"div">) {
  const classNames = cn("font-semibold text-foreground text-lg", className);
  return <div className={classNames} {...rest} />;
}
