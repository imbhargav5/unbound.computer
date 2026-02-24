import type { Control, FieldValues, Path } from "react-hook-form";
import {
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
} from "@/components/ui/form";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";

interface FormRadioGroupProps<TFieldValues extends FieldValues> {
  control: Control<TFieldValues>;
  description?: string;
  id: string;
  label: string;
  name: Path<TFieldValues>;
  options: { label: string; value: string }[];
}

export function FormRadioGroup<TFieldValues extends FieldValues>({
  id,
  label,
  control,
  name,
  description,
  options,
}: FormRadioGroupProps<TFieldValues>) {
  return (
    <FormField
      control={control}
      name={name}
      render={({ field }) => (
        <FormItem className="space-y-3">
          <FormLabel>{label}</FormLabel>
          <FormControl>
            <RadioGroup
              className="flex flex-col space-y-1"
              defaultValue={field.value}
              onValueChange={field.onChange}
            >
              {options.map((option) => (
                <FormItem
                  className="flex items-center space-x-3 space-y-0"
                  key={option.value}
                >
                  <FormControl>
                    <RadioGroupItem
                      id={`${id}-${option.value}`}
                      value={option.value}
                    />
                  </FormControl>
                  <FormLabel htmlFor={`${id}-${option.value}`}>
                    {option.label}
                  </FormLabel>
                </FormItem>
              ))}
            </RadioGroup>
          </FormControl>
          {description && <FormDescription>{description}</FormDescription>}
        </FormItem>
      )}
    />
  );
}
