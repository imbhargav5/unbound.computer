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

interface DataTablePaginationProps {
  onPageChange: (page: number) => void;
  onPageSizeChange: (pageSize: number) => void;
  page: number;
  pageSize: number;
  pageSizeOptions?: number[];
  totalItems: number;
}

export function DataTablePagination({
  page,
  pageSize,
  totalItems,
  onPageChange,
  onPageSizeChange,
  pageSizeOptions = [10, 20, 30, 40, 50],
}: DataTablePaginationProps) {
  const totalPages = Math.ceil(totalItems / pageSize) || 1;

  return (
    <div className="flex items-center justify-between px-2">
      <div className="flex items-center space-x-2">
        <p className="text-muted-foreground text-sm">Rows per page</p>
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
        <p className="text-muted-foreground text-sm">
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
