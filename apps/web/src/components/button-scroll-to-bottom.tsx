"use client";

import { ArrowDown } from "lucide-react";
import type { ComponentProps } from "react";
import { Button } from "@/components/ui/button";
import { useAtBottom } from "@/hooks/use-at-bottom";
import { cn } from "@/lib/utils";

export function ButtonScrollToBottom({
  className,
  ...props
}: ComponentProps<typeof Button>) {
  const isAtBottom = useAtBottom();

  return (
    <Button
      className={cn(
        "absolute top-1 right-4 z-10 bg-background transition-opacity duration-300 sm:right-8 md:top-2",
        isAtBottom ? "opacity-0" : "opacity-100",
        className
      )}
      onClick={() =>
        window.scrollTo({
          top: document.body.offsetHeight,
          behavior: "smooth",
        })
      }
      size="icon"
      variant="outline"
      {...props}
    >
      <ArrowDown />
      <span className="sr-only">Scroll to bottom</span>
    </Button>
  );
}
