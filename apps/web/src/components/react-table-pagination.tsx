"use client";

import {
  ChevronFirst,
  ChevronLast,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

interface ReactTablePaginationProps {
  page: number;
  pageSize: number;
  totalItems: number;
  onPageChange: (page: number) => void;
  onPageSizeChange: (pageSize: number) => void;
  pageSizeOptions?: number[];
}

export function ReactTablePagination({
  page,
  pageSize,
  totalItems,
  onPageChange,
  onPageSizeChange,
  pageSizeOptions = [10, 20, 30, 40, 50],
}: ReactTablePaginationProps) {
  const totalPages = Math.ceil(totalItems / pageSize);

  return (
    <div className="mt-4 flex items-center justify-between px-2">
      <div className="flex items-center space-x-2">
        <p className="font-medium text-sm">Rows per page</p>
        <Select
          onValueChange={(value) => {
            onPageSizeChange(Number(value));
          }}
          value={String(pageSize)}
        >
          <SelectTrigger className="h-8 w-[70px]">
            <SelectValue placeholder={pageSize} />
          </SelectTrigger>
          <SelectContent side="top">
            {pageSizeOptions.map((size) => (
              <SelectItem key={size} value={String(size)}>
                {size}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="flex items-center space-x-2">
        <p className="font-medium text-sm">
          Page {page} of {totalPages}
        </p>
        <div className="flex items-center space-x-1">
          <Button
            className="h-8 w-8"
            disabled={page === 1}
            onClick={() => onPageChange(1)}
            size="icon"
            variant="outline"
          >
            <ChevronFirst className="h-4 w-4" />
          </Button>
          <Button
            className="h-8 w-8"
            disabled={page === 1}
            onClick={() => onPageChange(page - 1)}
            size="icon"
            variant="outline"
          >
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button
            className="h-8 w-8"
            disabled={page === totalPages}
            onClick={() => onPageChange(page + 1)}
            size="icon"
            variant="outline"
          >
            <ChevronRight className="h-4 w-4" />
          </Button>
          <Button
            className="h-8 w-8"
            disabled={page === totalPages}
            onClick={() => onPageChange(totalPages)}
            size="icon"
            variant="outline"
          >
            <ChevronLast className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </div>
  );
}
