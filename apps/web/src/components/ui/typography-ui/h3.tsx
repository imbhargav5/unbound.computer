import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function H3({ className, ...rest }: ComponentProps<"h3">) {
  const classNames = cn(
    "mt-8 scroll-m-20 font-semibold text-2xl tracking-tight",
    className
  );
  return <h3 className={classNames} {...rest} />;
}
