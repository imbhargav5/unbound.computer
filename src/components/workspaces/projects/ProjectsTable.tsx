"use client";

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/compact-table";
import { CreateProjectDialog } from "@/components/CreateProjectDialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Typography } from "@/components/ui/Typography";
import { getProjectsClient } from "@/data/user/client/projects";
import type { Tables } from "@/lib/database.types";
import {
  projectsFilterSchema,
  type ProjectsFilterSchema,
} from "@/utils/zod-schemas/projects";
import { zodResolver } from "@hookform/resolvers/zod";
import { useQuery } from "@tanstack/react-query";
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
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { EditProjectForm } from "./EditProjectForm";

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
  const router = useRouter();
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({});
  const [editingProject, setEditingProject] =
    useState<Tables<"projects"> | null>(null);
  const [sorting, setSorting] = useState<SortingState>([]);

  const form = useForm<ProjectsFilterSchema>({
    resolver: zodResolver(projectsFilterSchema),
    defaultValues: {
      query: "",
      page: 1,
      perPage: 10,
      sorting: [],
    },
  });

  const { watch, register, setValue } = form;
  const query = watch("query");

  useEffect(() => {
    setValue("sorting", sorting);
  }, [sorting, setValue]);

  const {
    data: projectsData,
    isLoading,
    refetch: refetchProjects,
  } = useQuery({
    queryKey: ["projects", workspaceId, query, sorting],
    queryFn: () =>
      getProjectsClient({
        workspaceId,
        filters: {
          query,
          sorting,
          page: form.getValues("page"),
          perPage: form.getValues("perPage"),
        },
      }),
    staleTime: 1000 * 60 * 5,
    refetchOnWindowFocus: true,
    retry: 2,
  });

  const projects = projectsData?.data ?? [];

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
              router.push(`/project/${row.original.slug}`);
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
  console.log("render projects table");
  return (
    <div className="">
      <div className="bg-background p-2 flex justify-between items-center">
        <Typography.H3 className="my-0">Recent Projects</Typography.H3>
        <Link href={`/workspace/${workspaceId}/projects`}>
          <Button variant="link" size="sm">
            <span className="text-xs underline">View All</span>
          </Button>
        </Link>
      </div>
      <div className="p-2 border border-b-0">
        <div className="flex items-center space-x-2 justify-between">
          <div className="flex w-[300px] items-center  space-x-2">
            <Search className="h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search projects..."
              className="h-8"
              {...register("query")}
            />
          </div>
          <div className="flex items-center space-x-2">
            <CreateProjectDialog workspaceId={workspaceId} />
          </div>
        </div>
      </div>

      <div className="table-container [&>div]:rounded-none [&>div]:border-t-0 [&>div]:border-l-0 [&>div]:border-r-0">
        <Table>
          <TableHeader className="!rounded-none border">
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id} className="!rounded-none">
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id} className="!rounded-none">
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
          <TableBody className="!rounded-none">
            {isLoading ? (
              <TableRow className="!rounded-none">
                <TableCell
                  colSpan={columns.length}
                  className="h-24 text-center !rounded-none"
                >
                  Loading...
                </TableCell>
              </TableRow>
            ) : table.getRowModel().rows?.length ? (
              table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  data-state={row.getIsSelected() && "selected"}
                  onDoubleClick={() => setEditingProject(row.original)}
                  className="cursor-pointer !rounded-none"
                >
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id} className="!rounded-none">
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext(),
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow className="!rounded-none">
                <TableCell
                  colSpan={columns.length}
                  className="h-24 text-center !rounded-none"
                >
                  No projects found.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <EditProjectForm
        project={editingProject}
        key={editingProject?.id}
        onClose={() => setEditingProject(null)}
        onSuccess={refetchProjects}
      />
    </div>
  );
}
