import { cn } from "@/utils/cn";

export function MdxTable({
  className,
  ...props
}: React.TableHTMLAttributes<HTMLTableElement>) {
  return (
    <div className="overflow-x-auto">
      <table
        className={cn(
          className,
          "w-full table-auto border-collapse border-gray-200 dark:border-gray-700"
        )}
        {...props}
      />
    </div>
  );
}

export function MdxTableHeader({
  className,
  ...props
}: React.ThHTMLAttributes<HTMLTableHeaderCellElement>) {
  return (
    <th
      className={cn(
        className,
        "px-6 py-3 text-left font-medium text-gray-500 text-xs uppercase tracking-wider dark:text-gray-400"
      )}
      style={{ wordWrap: "break-word" }}
      {...props}
    />
  );
}

export function MdxTableCell({
  className,
  ...props
}: React.TdHTMLAttributes<HTMLTableDataCellElement>) {
  return (
    <td
      className={cn(
        className,
        "px-6 py-4 text-gray-900 text-sm dark:text-gray-100"
      )}
      style={{ wordWrap: "break-word" }}
      {...props}
    />
  );
}

export function MdxTableRow({
  className,
  ...props
}: React.HTMLAttributes<HTMLTableRowElement>) {
  return (
    <tr
      className={cn(className, "border-gray-200 border-t dark:border-gray-700")}
      {...props}
    />
  );
}
