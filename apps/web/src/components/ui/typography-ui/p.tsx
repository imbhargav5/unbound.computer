import { Slot } from "@radix-ui/react-slot";
import type { ComponentPropsWithoutRef } from "react";
import { cn } from "@/utils/cn";

export function P({
  className,
  asChild,
  ...rest
}: ComponentPropsWithoutRef<"p"> & {
  asChild?: boolean;
}) {
  const classNames = cn("leading-7", "&:not(:first-child):mt-6", className);
  const Component = asChild ? Slot : "p";
  return <Component className={classNames} {...rest} />;
}
