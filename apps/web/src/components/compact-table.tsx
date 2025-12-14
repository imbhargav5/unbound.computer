import * as React from "react";
import {
  TableCell as BaseTableCell,
  TableHead as BaseTableHead,
  TableRow as BaseTableRow,
  Table,
  TableBody,
  TableHeader,
} from "@/components/ui/table";
import { cn } from "@/lib/utils";

// Compact table uses the base Table which already has border container
// Just re-export with tighter padding overrides
const CompactTable = React.forwardRef<
  HTMLTableElement,
  React.HTMLAttributes<HTMLTableElement>
>(({ className, ...props }, ref) => (
  <Table className={cn(className)} ref={ref} {...props} />
));
CompactTable.displayName = "CompactTable";

const TableRow = React.forwardRef<
  HTMLTableRowElement,
  React.HTMLAttributes<HTMLTableRowElement>
>(({ className, ...props }, ref) => (
  <BaseTableRow className={cn(className)} ref={ref} {...props} />
));
TableRow.displayName = "TableRow";

const TableHead = React.forwardRef<
  HTMLTableCellElement,
  React.ThHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
  <BaseTableHead
    className={cn("h-9 px-2 py-1.5 text-xs", className)}
    ref={ref}
    {...props}
  />
));
TableHead.displayName = "TableHead";

const TableCell = React.forwardRef<
  HTMLTableCellElement,
  React.TdHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
  <BaseTableCell
    className={cn("px-2 py-1.5", className)}
    ref={ref}
    {...props}
  />
));
TableCell.displayName = "TableCell";

export {
  CompactTable as Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
};
