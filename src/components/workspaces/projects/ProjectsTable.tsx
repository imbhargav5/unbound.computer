"use client";

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/compact-table";
import { SmartSheet } from "@/components/smart-sheet";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { getProjectsClient } from "@/data/user/client/projects";
import {
  deleteProjectsAction,
  updateProjectAction,
} from "@/data/user/projects";
import type { Tables } from "@/lib/database.types";
import {
  ColumnDef,
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  type RowSelectionState,
  type SortingState,
} from "@tanstack/react-table";
import { format } from "date-fns";
import { CalendarDays, ChevronsUpDown, Clock, Search } from "lucide-react";
import { useAction } from "next-safe-action/hooks";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { ConfirmDeleteProjectsDialog } from "./ConfirmDeleteProjectsDialog";
import { ProjectForm } from "./ProjectForm";

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(timer);
    };
  }, [value, delay]);

  return debouncedValue;
}

const statusEmojis = {
  draft: "📝",
  pending_approval: "⏳",
  approved: "🏗️",
  completed: "✅",
} as const;

interface ProjectsTableProps {
  workspaceId: string;
}

export function ProjectsTable({ workspaceId }: ProjectsTableProps) {
  const [projects, setProjects] = useState<Tables<"projects">[]>([]);
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({});
  const [editingProject, setEditingProject] =
    useState<Tables<"projects"> | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [sorting, setSorting] = useState<SortingState>([]);
  const [isLoading, setIsLoading] = useState(true);

  const debouncedSearchQuery = useDebounce(searchQuery, 300);

  const { execute: executeDelete, status: deleteStatus } = useAction(
    deleteProjectsAction,
    {
      onSuccess: () => {
        toast.success("Projects deleted successfully");
        setRowSelection({});
        fetchProjects();
      },
      onError: (error) => {
        toast.error(error.error?.serverError || "Failed to delete projects");
      },
    },
  );

  const { execute: executeUpdate, status: updateStatus } = useAction(
    updateProjectAction,
    {
      onSuccess: () => {
        toast.success("Project updated successfully");
        setEditingProject(null);
        fetchProjects();
      },
      onError: (error) => {
        toast.error(error.error?.serverError || "Failed to update project");
      },
    },
  );

  const fetchProjects = useCallback(async () => {
    try {
      setIsLoading(true);
      const data = await getProjectsClient({
        workspaceId,
        query: debouncedSearchQuery,
        sorting,
      });
      setProjects(data);
    } catch (error) {
      console.error("Error fetching projects:", error);
      toast.error("Failed to fetch projects");
    } finally {
      setIsLoading(false);
    }
  }, [workspaceId, debouncedSearchQuery, sorting]);

  useEffect(() => {
    fetchProjects();
  }, [fetchProjects]);

  const columns: ColumnDef<Tables<"projects">>[] = [
    {
      id: "select",
      header: ({ table }) => (
        <Checkbox
          checked={table.getIsAllPageRowsSelected()}
          onCheckedChange={(value) => table.toggleAllPageRowsSelected(!!value)}
          aria-label="Select all"
        />
      ),
      cell: ({ row }) => (
        <Checkbox
          checked={row.getIsSelected()}
          onCheckedChange={(value) => row.toggleSelected(!!value)}
          aria-label="Select row"
        />
      ),
      enableSorting: false,
      enableHiding: false,
    },
    {
      accessorKey: "name",
      header: ({ column }) => (
        <Button
          variant="ghost"
          className="p-0 hover:bg-transparent"
          onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
        >
          <span className="font-semibold">Name</span>
          <ChevronsUpDown className="ml-1 h-4 w-4" />
        </Button>
      ),
      cell: ({ row }) => {
        return (
          <Button
            variant="ghost"
            className="p-0 hover:bg-transparent"
            onClick={() => {
              setEditingProject(row.original);
            }}
          >
            <span className="text-primary hover:underline">
              {row.getValue("name")}
            </span>
          </Button>
        );
      },
    },
    {
      accessorKey: "project_status",
      header: ({ column }) => (
        <Button
          variant="ghost"
          className="p-0 hover:bg-transparent"
          onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
        >
          <span className="font-semibold">Status</span>
          <ChevronsUpDown className="ml-1 h-4 w-4" />
        </Button>
      ),
      cell: ({ row }) => {
        const status = row.getValue(
          "project_status",
        ) as keyof typeof statusEmojis;
        return (
          <Badge variant="secondary" className="text-xs font-normal">
            {statusEmojis[status]}{" "}
            {status.charAt(0).toUpperCase() + status.slice(1)}
          </Badge>
        );
      },
    },
    {
      accessorKey: "created_at",
      header: "Created",
      cell: ({ row }) => (
        <div className="flex items-center text-xs text-muted-foreground">
          <CalendarDays className="mr-1 h-3 w-3" />
          {format(new Date(row.getValue("created_at")), "dd MMM yyyy")}
        </div>
      ),
    },
    {
      accessorKey: "updated_at",
      header: "Updated",
      cell: ({ row }) => (
        <div className="flex items-center text-xs text-muted-foreground">
          <Clock className="mr-1 h-3 w-3" />
          {format(new Date(row.getValue("updated_at")), "dd MMM yyyy")}
        </div>
      ),
    },
  ];

  const table = useReactTable({
    data: projects,
    columns,
    state: {
      rowSelection,
      sorting,
    },
    enableRowSelection: true,
    onRowSelectionChange: setRowSelection,
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });

  const selectedIds = Object.keys(rowSelection).map(
    (idx) => projects[parseInt(idx)].id,
  );

  const handleSubmit = async (values: {
    name: string;
    project_status: Tables<"projects">["project_status"];
  }) => {
    if (!editingProject) return;

    try {
      setIsSubmitting(true);
      await executeUpdate({
        projectId: editingProject.id,
        ...values,
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-2">
          <Search className="h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search projects..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="h-8 w-[150px] lg:w-[250px]"
          />
        </div>
        {selectedIds.length > 0 && (
          <div className="flex items-center space-x-2">
            <p className="text-sm text-muted-foreground">
              {selectedIds.length} selected
            </p>
            <ConfirmDeleteProjectsDialog
              selectedCount={selectedIds.length}
              onConfirm={() => executeDelete({ projectIds: selectedIds })}
              isDeleting={deleteStatus === "executing"}
            />
          </div>
        )}
      </div>

      <div className="rounded-md border">
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
                        header.getContext(),
                      )}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow>
                <TableCell
                  colSpan={columns.length}
                  className="h-24 text-center"
                >
                  Loading...
                </TableCell>
              </TableRow>
            ) : table.getRowModel().rows?.length ? (
              table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  data-state={row.getIsSelected() && "selected"}
                >
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext(),
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell
                  colSpan={columns.length}
                  className="h-24 text-center"
                >
                  No projects found.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {editingProject && (
        <SmartSheet
          open={!!editingProject}
          onOpenChange={() => setEditingProject(null)}
        >
          <div className="p-6">
            <h2 className="text-lg font-semibold mb-4">Edit Project</h2>
            <ProjectForm
              project={editingProject}
              onSubmit={handleSubmit}
              isSubmitting={isSubmitting}
            />
          </div>
        </SmartSheet>
      )}
    </div>
  );
}
