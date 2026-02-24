import type { Control, FieldValues, Path } from "react-hook-form";
import {
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Textarea } from "@/components/ui/textarea";

interface FormTextareaProps<TFieldValues extends FieldValues> {
  control: Control<TFieldValues>;
  description?: string;
  id: string;
  label: string;
  name: Path<TFieldValues>;
  placeholder?: string;
}

export function FormTextarea<TFieldValues extends FieldValues>({
  id,
  label,
  control,
  name,
  description,
  placeholder,
}: FormTextareaProps<TFieldValues>) {
  return (
    <FormField
      control={control}
      name={name}
      render={({ field }) => (
        <FormItem>
          <FormLabel htmlFor={id}>{label}</FormLabel>
          <FormControl>
            <Textarea id={id} placeholder={placeholder} {...field} />
          </FormControl>
          {description && <FormDescription>{description}</FormDescription>}
          <FormMessage />
        </FormItem>
      )}
    />
  );
}
