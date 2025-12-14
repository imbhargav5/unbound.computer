import type { ComponentProps } from "react";
import { cn } from "@/utils/cn";

export function List({ className, ...rest }: ComponentProps<"ul">) {
  const classNames = cn("my-6 ml-6 list-disc [&>li]:mt-2", className);
  return <ul className={classNames} {...rest} />;
}
