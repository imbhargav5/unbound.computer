import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function H1({ className, ...rest }: ComponentProps<"h1">) {
  const classNames = cn(
    "scroll-m-20 font-extrabold text-4xl tracking-tight lg:text-5xl",
    className
  );
  return <h1 className={classNames} {...rest} />;
}
