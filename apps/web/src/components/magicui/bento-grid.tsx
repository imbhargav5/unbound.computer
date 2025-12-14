import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

const BentoGrid = ({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) => (
  <div
    className={cn("grid w-full auto-rows-[22rem] grid-cols-3 gap-4", className)}
  >
    {children}
  </div>
);

const BentoCard = ({
  name,
  className,
  background,
  description,
}: {
  name: string;
  className?: string;
  background: ReactNode;
  description: string;
}) => (
  <div
    className={cn(
      "group relative flex flex-col justify-between overflow-hidden rounded-xl",
      // light styles
      "bg-white [box-shadow:0_0_0_1px_rgba(0,0,0,.03),0_2px_4px_rgba(0,0,0,.05),0_12px_24px_rgba(0,0,0,.05)]",
      // dark styles
      "transform-gpu dark:bg-black dark:[border:1px_solid_rgba(255,255,255,.1)] dark:[box-shadow:0_-20px_80px_-20px_#ffffff1f_inset]",
      className
    )}
    key={name}
  >
    <div>{background}</div>
    <div className="pointer-events-none z-10 flex transform-gpu flex-col gap-1 bg-background p-6">
      <h3 className="font-semibold text-xl">{name}</h3>
      <p className="max-w-lg text-slate-500 leading-relaxed dark:text-slate-400">
        {description}
      </p>
    </div>
  </div>
);

export { BentoCard, BentoGrid };
