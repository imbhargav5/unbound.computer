"use client";
import { X } from "lucide-react";
import * as React from "react";
import { Badge } from "@/components/ui/badge";
import {
  Command,
  CommandGroup,
  CommandInput,
  CommandItem,
} from "@/components/ui/command";

type Option = {
  value: string;
  label: string;
};

type MultiSelectProps = {
  options: Option[];
  selected: string[];
  onChange: (selected: string[]) => void;
  placeholder?: string;
};

export function MultiSelect({
  options,
  selected = [],
  onChange,
  placeholder = "Select items...",
}: MultiSelectProps) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [open, setOpen] = React.useState(false);
  const [inputValue, setInputValue] = React.useState("");

  // Ensure selected is always an array
  const safeSelected = Array.isArray(selected) ? selected : [];

  const handleUnselect = React.useCallback(
    (item: string) => {
      onChange(safeSelected.filter((i) => i !== item));
    },
    [onChange, safeSelected]
  );

  const handleKeyDown = React.useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      const input = inputRef.current;
      if (input) {
        if (
          (e.key === "Delete" || e.key === "Backspace") &&
          input.value === "" &&
          safeSelected.length > 0
        ) {
          const newSelected = [...safeSelected];
          newSelected.pop();
          onChange(newSelected);
        }
        if (e.key === "Escape") {
          input.blur();
        }
      }
    },
    [onChange, safeSelected]
  );

  const selectables = React.useMemo(
    () => options.filter((item) => !safeSelected.includes(item.value)),
    [options, safeSelected]
  );

  return (
    <Command
      className="overflow-visible bg-transparent"
      onKeyDown={handleKeyDown}
    >
      <div className="group rounded-md border border-input px-3 py-2 text-sm ring-offset-background focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2">
        <div className="flex flex-wrap gap-1">
          {safeSelected.map((item) => {
            const option = options.find((option) => option.value === item);
            return (
              <Badge key={item} variant="secondary">
                {option?.label}
                <button
                  className="ml-1 rounded-full outline-hidden ring-offset-background focus:ring-2 focus:ring-ring focus:ring-offset-2"
                  onClick={() => handleUnselect(item)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      handleUnselect(item);
                    }
                  }}
                  onMouseDown={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                  }}
                >
                  <X className="h-3 w-3 text-muted-foreground hover:text-foreground" />
                </button>
              </Badge>
            );
          })}
          <CommandInput
            className="ml-2 flex-1 bg-transparent outline-hidden placeholder:text-muted-foreground"
            onBlur={() => setOpen(false)}
            onFocus={() => setOpen(true)}
            onValueChange={setInputValue}
            placeholder={placeholder}
            ref={inputRef}
            value={inputValue}
          />
        </div>
      </div>
      <div className="relative mt-2">
        {open && selectables.length > 0 && (
          <div className="absolute top-0 z-10 w-full animate-in rounded-md border bg-popover text-popover-foreground shadow-md outline-hidden">
            <CommandGroup className="h-full overflow-auto">
              {selectables.map((option) => (
                <CommandItem
                  className="cursor-pointer"
                  key={option.value}
                  onMouseDown={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                  }}
                  onSelect={() => {
                    setInputValue("");
                    onChange([...safeSelected, option.value]);
                  }}
                >
                  {option.label}
                </CommandItem>
              ))}
            </CommandGroup>
          </div>
        )}
      </div>
    </Command>
  );
}
