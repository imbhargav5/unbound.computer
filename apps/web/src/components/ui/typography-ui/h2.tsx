import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function H2({ className, ...rest }: ComponentProps<"h2">) {
  const classNames = cn(
    "mt-10 scroll-m-20 pb-2 font-semibold text-3xl tracking-tight transition-colors first:mt-0 dark:border-b-neutral-700",
    className
  );
  return <h2 className={classNames} {...rest} />;
}
