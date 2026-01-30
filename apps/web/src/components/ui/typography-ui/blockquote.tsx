import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function Blockquote({
  className,
  ...rest
}: ComponentProps<"blockquote">) {
  const classNames = cn(
    "mt-6 border-slate-300 border-l-2 pl-6 text-slate-800 italic dark:border-slate-600 dark:text-slate-200",
    className
  );
  return <blockquote className={classNames} {...rest} />;
}
