'use client';

import { usePathname, useRouter, useSearchParams } from 'next/navigation';

import { Cross2Icon } from '@radix-ui/react-icons';

import FacetedFilter from '@/components/FacetedFilter';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

import { Toggle } from '@/components/ui/toggle';
import {
  NEW_PRIORITY_OPTIONS,
  NEW_STATUS_OPTIONS,
  NEW_TYPE_OPTIONS,
} from '@/utils/feedback';
import { CircleUser } from 'lucide-react';
import {
  feedbackPrioritiesSchema,
  feedbackStatusesSchema,
  feedbackTypesSchema,
  sortSchema,
  type FeedbackDropdownFiltersSchema,
  type FeedbackSortSchema,
} from './schema';

export function FeedbackFacetedFilters() {
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const { replace } = useRouter();

  const filters: FeedbackDropdownFiltersSchema = {
    statuses: feedbackStatusesSchema.parse(
      searchParams?.get('statuses')?.split(',') || [],
    ),
    types: feedbackTypesSchema.parse(
      searchParams?.get('types')?.split(',') || [],
    ),
    priorities: feedbackPrioritiesSchema.parse(
      searchParams?.get('priorities')?.split(',') || [],
    ),
    myFeedbacks: Boolean(searchParams?.get('myFeedbacks')) || false,
  };

  const setFilters = (newFilters: FeedbackDropdownFiltersSchema) => {
    const params = new URLSearchParams(searchParams ?? undefined);
    for (const [key, value] of Object.entries(newFilters)) {
      if (key === 'myFeedbacks') {
        if (newFilters.myFeedbacks) {
          params.set(key, newFilters.myFeedbacks.toString());
        } else {
          params.delete(key);
        }
        continue;
      }
      if (Array.isArray(value) && value.length) {
        params.set(key, value.join(','));
      } else {
        params.delete(key);
      }
    }
    params.set('page', '1');
    replace(`${pathname}?${params.toString()}`);
  };

  const setSort = (newSort: FeedbackSortSchema) => {
    const params = new URLSearchParams(searchParams ?? undefined);
    if (newSort) {
      params.set('sort', newSort);
    } else {
      params.delete('sort');
    }

    params.set('page', '1');
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
        title="Status"
        options={NEW_STATUS_OPTIONS}
        selectedValues={new Set(filters.statuses)}
        onSelectCb={(values) => {
          setFilters({
            ...filters,
            statuses: values,
          });
        }}
      />
      <FacetedFilter
        title="Type"
        options={NEW_TYPE_OPTIONS}
        selectedValues={new Set(filters.types)}
        onSelectCb={(values) => {
          setFilters({
            ...filters,
            types: values,
          });
        }}
      />
      <FacetedFilter
        title="Priority"
        options={NEW_PRIORITY_OPTIONS}
        selectedValues={new Set(filters.priorities)}
        onSelectCb={(values) => {
          setFilters({
            ...filters,
            priorities: values,
          });
        }}
      />
      <Toggle
        variant={'outline'}
        className="h-8 px-2 flex gap-2 lg:px-3 rounded-md"
        defaultPressed={filters.myFeedbacks}
        onClick={() => {
          setFilters({
            ...filters,
            myFeedbacks: filters.myFeedbacks ? !filters.myFeedbacks : true,
          });
        }}
      >
        <CircleUser className="h-4 w-4" />
        My feedbacks
      </Toggle>
      {(Boolean(filters.statuses?.length) ||
        Boolean(filters.types?.length) ||
        Boolean(filters.priorities?.length)) && (
          <Button
            variant="ghost"
            onClick={() => {
              setFilters({
                statuses: [],
                types: [],
                priorities: [],
                myFeedbacks: false,
              });
            }}
            className="h-8 px-2 lg:px-3"
          >
            Reset
            <Cross2Icon className="ml-2 h-4 w-4" />
          </Button>
        )}
    </div>
  );
}

export function FeedbackFacetedFiltersFallback() {
  return <p>Feedback fallback</p>;
}
