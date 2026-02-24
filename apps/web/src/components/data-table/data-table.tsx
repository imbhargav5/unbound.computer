"use client";

import {
  type ColumnDef,
  flexRender,
  getCoreRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  type PaginationState,
  type SortingState,
  useReactTable,
} from "@tanstack/react-table";
import { useState } from "react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { DataTablePagination } from "./data-table-pagination";

interface DataTableProps<TData, TValue> {
  columns: ColumnDef<TData, TValue>[];
  data: TData[];
  emptyMessage?: string;
  enablePagination?: boolean;
  // Optional features
  enableSorting?: boolean;
  initialPagination?: PaginationState;
  // Loading state
  isLoading?: boolean;
  manualPagination?: boolean;
  onPaginationChange?: (pagination: PaginationState) => void;
  // Server-side pagination
  pageCount?: number;
}

export function DataTable<TData, TValue>({
  columns,
  data,
  enableSorting = true,
  enablePagination = false,
  pageCount,
  manualPagination = false,
  onPaginationChange,
  initialPagination = { pageIndex: 0, pageSize: 10 },
  isLoading = false,
  emptyMessage = "No results found.",
}: DataTableProps<TData, TValue>) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const [pagination, setPagination] =
    useState<PaginationState>(initialPagination);

  const table = useReactTable({
    data,
    columns,
    state: {
      sorting: enableSorting ? sorting : undefined,
      pagination: enablePagination ? pagination : undefined,
    },
    pageCount: manualPagination ? pageCount : undefined,
    manualPagination,
    onSortingChange: enableSorting ? setSorting : undefined,
    onPaginationChange: enablePagination
      ? (updater) => {
          const newPagination =
            typeof updater === "function" ? updater(pagination) : updater;
          setPagination(newPagination);
          onPaginationChange?.(newPagination);
        }
      : undefined,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: enableSorting ? getSortedRowModel() : undefined,
    getPaginationRowModel:
      enablePagination && !manualPagination
        ? getPaginationRowModel()
        : undefined,
  });

  return (
    <div className="space-y-4">
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((headerGroup) => (
            <TableRow key={headerGroup.id}>
              {headerGroup.headers.map((header) => (
                <TableHead key={header.id}>
                  {header.isPlaceholder
                    ? null
                    : flexRender(
                        header.column.columnDef.header,
                        header.getContext()
                      )}
                </TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {isLoading ? (
            <TableRow>
              <TableCell className="h-24 text-center" colSpan={columns.length}>
                Loading...
              </TableCell>
            </TableRow>
          ) : table.getRowModel().rows?.length ? (
            table.getRowModel().rows.map((row) => (
              <TableRow
                data-state={row.getIsSelected() && "selected"}
                key={row.id}
              >
                {row.getVisibleCells().map((cell) => (
                  <TableCell key={cell.id}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </TableCell>
                ))}
              </TableRow>
            ))
          ) : (
            <TableRow>
              <TableCell className="h-24 text-center" colSpan={columns.length}>
                {emptyMessage}
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>

      {enablePagination && (
        <DataTablePagination
          onPageChange={(page) => table.setPageIndex(page - 1)}
          onPageSizeChange={(size) => {
            table.setPageSize(size);
          }}
          page={pagination.pageIndex + 1}
          pageSize={pagination.pageSize}
          totalItems={
            manualPagination
              ? (pageCount ?? 0) * pagination.pageSize
              : data.length
          }
        />
      )}
    </div>
  );
}
