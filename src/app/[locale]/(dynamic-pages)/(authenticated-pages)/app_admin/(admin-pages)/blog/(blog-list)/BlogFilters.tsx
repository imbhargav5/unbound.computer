"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";


import FacetedFilter from "@/components/FacetedFilter";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";


import type { BlogFiltersSchema } from "./page";
import { sortSchema, type BlogSortSchema } from "./schema";

type BlogFacetedFiltersProps = {
  tags: string[];
};

export function BlogFacetedFilters({ tags }: BlogFacetedFiltersProps) {
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const { replace } = useRouter();

  const filters: BlogFiltersSchema = {
    keywords: searchParams?.get("keywords")?.split(",") || [],
  };

  const setFilters = (newFilters: BlogFiltersSchema) => {
    const params = new URLSearchParams(searchParams ?? undefined);
    params.set("page", "1");
    replace(`${pathname}?${params.toString()}`);

    for (const [key] of Object.entries(newFilters)) {
      if (key === "keywords") {
        if (newFilters.keywords) {
          params.set(key, newFilters.keywords.join(","));
        } else {
          params.delete(key);
        }
      }
    }
  };

  const setSort = (newSort: BlogSortSchema) => {
    const params = new URLSearchParams(searchParams ?? undefined);
    if (newSort) {
      params.set("sort", newSort);
    } else {
      params.delete("sort");
    }

    params.set("page", "1");
    replace(`${pathname}?${params.toString()}`);
  };
  return (
    <div className="flex gap-2 flex-wrap">
      <Select
        onValueChange={(val) => {
          const parsedValue = sortSchema.parse(val);
          setSort(parsedValue);
        }}
      >
        <SelectTrigger className="w-fit h-8">
          <SelectValue placeholder="Sort" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="desc">Recent First</SelectItem>
          <SelectItem value="asc">Oldest First</SelectItem>
        </SelectContent>
      </Select>
      <FacetedFilter
        title="Keywords"
        options={tags.map(tag => ({
          label: tag,
          value: tag,
        }))}
        selectedValues={new Set(filters.keywords)}
        onSelectCb={(values) => {
          setFilters({
            ...filters,
            keywords: values,
          });
        }}
      />
    </div>
  );
}

export function BlogFacetedFiltersFallback() {
  return <p>Blog fallback</p>;
}
