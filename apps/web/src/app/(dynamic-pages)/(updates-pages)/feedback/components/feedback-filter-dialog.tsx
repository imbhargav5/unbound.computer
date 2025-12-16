"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import {
  NEW_PRIORITY_OPTIONS,
  NEW_STATUS_OPTIONS,
  NEW_TYPE_OPTIONS,
} from "@/utils/feedback";

interface FilterState {
  query: string;
  statuses: string[];
  types: string[];
  priorities: string[];
}

export function FeedbackFilterDialog() {
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const { replace } = useRouter();
  const [open, setOpen] = useState(false);

  const [filters, setFilters] = useState<FilterState>({
    query: searchParams?.get("query") || "",
    statuses: searchParams?.get("statuses")?.split(",") || [],
    types: searchParams?.get("types")?.split(",") || [],
    priorities: searchParams?.get("priorities")?.split(",") || [],
  });

  const handleSubmit = () => {
    const params = new URLSearchParams();
    if (filters.query) params.set("query", filters.query);
    if (filters.statuses.length)
      params.set("statuses", filters.statuses.join(","));
    if (filters.types.length) params.set("types", filters.types.join(","));
    if (filters.priorities.length)
      params.set("priorities", filters.priorities.join(","));

    params.set("page", "1");
    replace(`${pathname}?${params.toString()}`);
    setOpen(false);
  };

  const handleToggleOption = (category: keyof FilterState, value: string) => {
    setFilters((prev) => {
      const current = prev[category] as string[];
      return {
        ...prev,
        [category]: current.includes(value)
          ? current.filter((v) => v !== value)
          : [...current, value],
      };
    });
  };

  const getActiveFiltersCount = () =>
    (filters.query ? 1 : 0) +
    filters.statuses.length +
    filters.types.length +
    filters.priorities.length;

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button
          className="h-auto w-full justify-start rounded-none px-4 py-3"
          data-testid="filter-dialog-trigger"
          variant="ghost"
        >
          Search
          {getActiveFiltersCount() > 0 && (
            <span className="ml-2 rounded-full bg-primary px-2 py-0.5 text-primary-foreground text-xs">
              {getActiveFiltersCount()}
            </span>
          )}
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Filter Feedback</DialogTitle>
        </DialogHeader>
        <div className="max-h-[60vh] space-y-4 overflow-y-auto py-4">
          <div className="space-y-2 p-1">
            <div className={cn("relative flex flex-1")}>
              <label className="sr-only" htmlFor="search">
                Search
              </label>
              <Input
                className="block"
                data-testid="filter-search-input"
                defaultValue={searchParams?.get("query")?.toString()}
                onChange={(e) => {
                  setFilters((prev) => ({ ...prev, query: e.target.value }));
                }}
                placeholder="Search Feedback..."
              />
            </div>
          </div>

          <Separator />

          <div className="space-y-2">
            <h4 className="font-medium">Status</h4>
            {NEW_STATUS_OPTIONS.map((option) => (
              <div className="flex items-center space-x-2" key={option.value}>
                <Checkbox
                  checked={filters.statuses.includes(option.value)}
                  data-testid={`filter-status-${option.value}`}
                  id={`status-${option.value}`}
                  onCheckedChange={() =>
                    handleToggleOption("statuses", option.value)
                  }
                />
                <label
                  className="flex items-center gap-2 text-sm"
                  htmlFor={`status-${option.value}`}
                >
                  <option.icon className="h-3 w-3" />
                  {option.label}
                </label>
              </div>
            ))}
          </div>

          <Separator />

          <div className="space-y-2">
            <h4 className="font-medium">Type</h4>
            {NEW_TYPE_OPTIONS.map((option) => (
              <div className="flex items-center space-x-2" key={option.value}>
                <Checkbox
                  checked={filters.types.includes(option.value)}
                  data-testid={`filter-type-${option.value}`}
                  id={`type-${option.value}`}
                  onCheckedChange={() =>
                    handleToggleOption("types", option.value)
                  }
                />
                <label
                  className="flex items-center gap-2 text-sm"
                  htmlFor={`type-${option.value}`}
                >
                  <option.icon className="h-3 w-3" />
                  {option.label}
                </label>
              </div>
            ))}
          </div>

          <Separator />

          <div className="space-y-2">
            <h4 className="font-medium">Priority</h4>
            {NEW_PRIORITY_OPTIONS.map((option) => (
              <div className="flex items-center space-x-2" key={option.value}>
                <Checkbox
                  checked={filters.priorities.includes(option.value)}
                  data-testid={`filter-priority-${option.value}`}
                  id={`priority-${option.value}`}
                  onCheckedChange={() =>
                    handleToggleOption("priorities", option.value)
                  }
                />
                <label
                  className="flex items-center gap-2 text-sm"
                  htmlFor={`priority-${option.value}`}
                >
                  <option.icon className="h-3 w-3" />
                  {option.label}
                </label>
              </div>
            ))}
          </div>
        </div>
        <DialogFooter>
          <Button
            data-testid="filter-reset-button"
            onClick={() => {
              setFilters({
                query: "",
                statuses: [],
                types: [],
                priorities: [],
              });
            }}
            variant="outline"
          >
            Reset
          </Button>
          <Button data-testid="filter-apply-button" onClick={handleSubmit}>
            Apply Filters
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
