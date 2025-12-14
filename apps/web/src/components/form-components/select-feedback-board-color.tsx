"use client";

import { Check } from "lucide-react";
import type { Control, FieldValues, Path } from "react-hook-form";
import {
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
} from "@/components/ui/form";
import {
  FEEDBACK_BG_BOARD_COLORS,
  getFeedbackBoardColorClass,
} from "@/constants";
import { cn } from "@/utils/cn";

interface SelectFeedbackBoardColorProps<TFieldValues extends FieldValues> {
  control: Control<TFieldValues>;
  name: Path<TFieldValues>;
  label?: string;
  description?: string;
}

export function SelectFeedbackBoardColor<TFieldValues extends FieldValues>({
  control,
  name,
  label,
  description,
}: SelectFeedbackBoardColorProps<TFieldValues>) {
  return (
    <FormField
      control={control}
      name={name}
      render={({ field }) => (
        <FormItem>
          {label && <FormLabel>{label}</FormLabel>}
          <FormControl>
            <div className="flex flex-wrap gap-2">
              {Object.entries(FEEDBACK_BG_BOARD_COLORS).map(([colorKey]) => (
                <button
                  className={cn(
                    "flex h-4 w-4 items-center justify-center rounded-full transition-all",
                    getFeedbackBoardColorClass(colorKey),
                    field.value === colorKey
                      ? "ring-2 ring-black ring-offset-2 dark:ring-white"
                      : "hover:ring-2 hover:ring-gray-400 hover:ring-offset-2"
                  )}
                  key={colorKey}
                  onClick={() => field.onChange(colorKey)}
                  type="button"
                >
                  {field.value === colorKey && (
                    <Check className="h-3 w-3 text-white" />
                  )}
                </button>
              ))}
            </div>
          </FormControl>
          {description && <FormDescription>{description}</FormDescription>}
        </FormItem>
      )}
    />
  );
}
