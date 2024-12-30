import {
  TableCell as BaseTableCell,
  TableHead as BaseTableHead,
  TableRow as BaseTableRow,
  Table,
  TableBody,
  TableHeader,
} from "@/components/ui/table";
import { cn } from "@/lib/utils";
import * as React from "react";

const CompactTable = React.forwardRef<
  HTMLTableElement,
  React.HTMLAttributes<HTMLTableElement>
>(({ className, ...props }, ref) => (
  <div className="rounded-sm border">
    <Table ref={ref} className={cn("text-xs", className)} {...props} />
  </div>
));
CompactTable.displayName = "CompactTable";

const TableRow = React.forwardRef<
  HTMLTableRowElement,
  React.HTMLAttributes<HTMLTableRowElement>
>(({ className, ...props }, ref) => (
  <BaseTableRow
    ref={ref}
    className={cn("hover:bg-muted/50", className)}
    {...props}
  />
));
TableRow.displayName = "TableRow";

const TableHead = React.forwardRef<
  HTMLTableCellElement,
  React.ThHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
  <BaseTableHead
    ref={ref}
    className={cn("h-8 bg-muted px-2 py-0 text-xs font-medium", className)}
    {...props}
  />
));
TableHead.displayName = "TableHead";

const TableCell = React.forwardRef<
  HTMLTableCellElement,
  React.TdHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
  <BaseTableCell
    ref={ref}
    className={cn("h-8 border-x px-2 py-0", className)}
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
  TableRow
};

