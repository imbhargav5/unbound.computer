import type { ComponentPropsWithoutRef } from "react";
import type { Control, FieldValues, Path } from "react-hook-form";
import {
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";

type AuthFormInputProps<TFieldValues extends FieldValues> = {
  id: string;
  control: Control<TFieldValues>;
  name: Path<TFieldValues>;
  description?: string;
  type?: string;
  placeholder?: string;
  inputProps?: Omit<
    ComponentPropsWithoutRef<typeof Input>,
    "id" | "name" | "type" | "placeholder"
  >;
};

export function AuthFormInput<TFieldValues extends FieldValues>({
  id,
  control,
  name,
  description,
  type,
  placeholder,
  inputProps,
  ...restProps
}: AuthFormInputProps<TFieldValues>) {
  return (
    <FormField
      control={control}
      name={name}
      render={({ field }) => (
        <FormItem>
          <FormControl>
            <Input
              id={id}
              placeholder={placeholder}
              type={type}
              {...inputProps}
              {...field}
            />
          </FormControl>
          {description && <FormDescription>{description}</FormDescription>}
          <FormMessage />
        </FormItem>
      )}
    />
  );
}
