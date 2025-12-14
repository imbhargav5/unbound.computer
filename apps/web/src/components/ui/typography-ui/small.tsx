import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function Small({ className, ...rest }: ComponentProps<"small">) {
  const classNames = cn("font-medium text-sm leading-none", className);
  return <small className={classNames} {...rest} />;
}
