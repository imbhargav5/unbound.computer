import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function H4({ className, ...rest }: ComponentProps<"h4">) {
  const classNames = cn(
    "mt-8 scroll-m-20 font-semibold text-xl tracking-tight",
    className
  );
  return <h4 className={classNames} {...rest} />;
}
