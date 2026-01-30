import React from "react";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";

interface Step {
  name: string;
  icon: React.ReactNode;
  isActive: boolean;
}

interface StepperProps {
  steps: Step[];
  onStepChangeRequest?: (index: number) => void;
}

export function Stepper({ steps, onStepChangeRequest }: StepperProps) {
  return (
    <ol className="flex w-full items-center text-center font-medium text-muted-foreground text-sm sm:text-base">
      {steps.map((step, index) => (
        <React.Fragment key={step.name}>
          <li
            className={cn(
              "flex items-center",
              step.isActive
                ? "text-primary"
                : "text-muted-foreground opacity-50",
              onStepChangeRequest &&
                "cursor-pointer transition-colors duration-200 hover:text-primary"
            )}
            onClick={() => onStepChangeRequest && onStepChangeRequest(index)}
          >
            <span className="relative flex items-center after:mx-2 after:text-gray-200 after:content-['/'] sm:after:hidden dark:after:text-gray-500">
              {step.icon}
              {step.name}{" "}
              <span className="hidden sm:ms-2 sm:inline-flex">Info</span>
            </span>
            {index < steps.length - 1 && (
              <Separator
                className="mx-6 hidden w-[40px] sm:block xl:mx-10"
                orientation="horizontal"
              />
            )}
          </li>
        </React.Fragment>
      ))}
    </ol>
  );
}
