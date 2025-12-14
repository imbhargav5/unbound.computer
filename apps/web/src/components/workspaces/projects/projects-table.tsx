"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useQuery } from "@tanstack/react-query";
import {
  type ColumnDef,
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  type RowSelectionState,
  type SortingState,
  useReactTable,
} from "@tanstack/react-table";
import type { Tables } from "database/types";
import { format } from "date-fns";
import { CalendarDays, ChevronsUpDown, Clock } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/compact-table";
import { CreateProjectDialog } from "@/components/create-project-dialog";
import FacetedFilter from "@/components/faceted-filter";
import { ReactTablePagination } from "@/components/react-table-pagination";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Form } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Typography } from "@/components/ui/typography-ui";
import { getProjectsClient } from "@/data/user/client/projects";
import { useRouter } from "@/i18n/navigation";
import { getQueryClient } from "@/lib/query-client";
import type { Enum } from "@/types";
import { getIsWorkspaceAdmin } from "@/utils/workspaces";
import {
  type ProjectsFilterFormSchema,
  projectsFilterFormSchema,
} from "@/utils/zod-schemas/projects";
import { ConfirmDeleteProjectsDialog } from "./confirm-delete-projects-dialog";
import { EditProjectForm } from "./edit-project-form";

const statusEmojis = {
  draft: "📝",
  pending_approval: "⏳",
  approved: "🏗️",
  completed: "✅",
} as const;

const STATUS_OPTIONS: {
  label: string;
  value: Enum<"project_status">;
  icon?: React.ComponentType<{ className?: string }>;
}[] = [
  { label: "Draft", value: "draft", icon: undefined },
  { label: "Pending Approval", value: "pending_approval", icon: undefined },
  { label: "Approved", value: "approved", icon: undefined },
  { label: "Completed", value: "completed", icon: undefined },
];

interface ProjectsTableProps {
  workspaceId: string;
  workspaceRole: Enum<"workspace_member_role_type">;
}

export function ProjectsTable({
  workspaceId,
  workspaceRole,
}: ProjectsTableProps) {
  const router = useRouter();
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({});
  const [editingProject, setEditingProject] =
    useState<Tables<"projects"> | null>(null);
  const [sorting, setSorting] = useState<SortingState>([]);
  const [selectedStatuses, setSelectedStatuses] = useState<
    Set<Enum<"project_status">>
  >(new Set());
  const [{ pageIndex, pageSize }, setPagination] = useState({
    pageIndex: 0,
    pageSize: 10,
  });
  const queryClient = getQueryClient();
  const isWorkspaceAdmin = getIsWorkspaceAdmin(workspaceRole);

  const form = useForm<ProjectsFilterFormSchema>({
    resolver: zodResolver(projectsFilterFormSchema),
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

  useEffect(() => {
    setValue("page", pageIndex + 1);
    setValue("perPage", pageSize);
  }, [pageIndex, pageSize, setValue]);

  const {
    data: projectsData,
    isLoading,
    refetch: refetchProjects,
  } = useQuery(
    {
      queryKey: [
        "projects",
        workspaceId,
        query,
        sorting,
        pageIndex,
        pageSize,
        Array.from(selectedStatuses),
      ],
      queryFn: () =>
        getProjectsClient({
          workspaceId,
          filters: {
            query: query ?? "",
            sorting,
            page: form.getValues("page") ?? 1,
            perPage: form.getValues("perPage") ?? 10,
            statuses: Array.from(selectedStatuses),
          },
        }),
      staleTime: 1000 * 60 * 5,
      refetchOnWindowFocus: true,
      retry: 2,
    },
    queryClient
  );

  const projects = projectsData?.data ?? [];
  const totalProjects = projectsData?.count ?? 0;

  const columns: ColumnDef<Tables<"projects">>[] = [
    {
      id: "select",
      header: ({ table }) => (
        <Checkbox
          aria-label="Select all"
          checked={table.getIsAllPageRowsSelected()}
          onCheckedChange={(value) => table.toggleAllPageRowsSelected(!!value)}
        />
      ),
      cell: ({ row }) => (
        <Checkbox
          aria-label="Select row"
          checked={row.getIsSelected()}
          onCheckedChange={(value) => row.toggleSelected(!!value)}
        />
      ),
      enableSorting: false,
      enableHiding: false,
    },
    {
      accessorKey: "name",
      header: ({ column }) => (
        <Button
          className="p-0 hover:bg-transparent"
          onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          variant="ghost"
        >
          <span className="font-semibold">Name</span>
          <ChevronsUpDown className="ml-1 h-4 w-4" />
        </Button>
      ),
      cell: ({ row }) => (
        <Button
          className="p-0 hover:bg-transparent"
          onClick={() => {
            router.push(`/project/${row.original.slug}`);
          }}
          variant="ghost"
        >
          <span className="text-primary hover:underline">
            {row.getValue("name")}
          </span>
        </Button>
      ),
    },
    {
      accessorKey: "project_status",
      header: ({ column }) => (
        <Button
          className="p-0 hover:bg-transparent"
          onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          variant="ghost"
        >
          <span className="font-semibold">Status</span>
          <ChevronsUpDown className="ml-1 h-4 w-4" />
        </Button>
      ),
      cell: ({ row }) => {
        const status = row.getValue(
          "project_status"
        ) as keyof typeof statusEmojis;
        const formattedStatus = status
          .split("_")
          .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
          .join(" ");

        return (
          <div className="flex items-center space-x-1.5 text-sm">
            <span>{statusEmojis[status]}</span>
            <span>{formattedStatus}</span>
          </div>
        );
      },
    },
    {
      accessorKey: "created_at",
      header: ({ column }) => (
        <Button
          className="p-0 hover:bg-transparent"
          onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          variant="ghost"
        >
          <span className="font-semibold">Created</span>
          <ChevronsUpDown className="ml-1 h-4 w-4" />
        </Button>
      ),
      cell: ({ row }) => (
        <div className="flex items-center text-muted-foreground text-xs">
          <CalendarDays className="mr-1 h-3 w-3" />
          {format(new Date(row.getValue("created_at")), "dd MMM yyyy")}
        </div>
      ),
    },
    {
      accessorKey: "updated_at",
      header: ({ column }) => (
        <Button
          className="p-0 hover:bg-transparent"
          onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          variant="ghost"
        >
          <span className="font-semibold">Updated</span>
          <ChevronsUpDown className="ml-1 h-4 w-4" />
        </Button>
      ),
      cell: ({ row }) => (
        <div className="flex items-center text-muted-foreground text-xs">
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
      pagination: {
        pageIndex,
        pageSize,
      },
    },
    pageCount: Math.ceil(totalProjects / pageSize),
    enableRowSelection: true,
    manualPagination: true,
    onRowSelectionChange: setRowSelection,
    onSortingChange: setSorting,
    onPaginationChange: setPagination,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });

  // Check if user can modify projects (not readonly)
  const canModifyProjects = workspaceRole !== "readonly";
  return (
    <div className="">
      <div className="mb-2 flex items-end justify-between bg-background p-2">
        <div>
          <Typography.H2 className="my-0">Projects</Typography.H2>
          <Typography.Subtle>
            {canModifyProjects
              ? "Manage your projects here. You can double click on a project to view and edit it."
              : "View projects here. You have read-only access to this workspace."}
            {isWorkspaceAdmin &&
              " You can delete projects by selecting them and choosing the delete action."}
          </Typography.Subtle>
        </div>
        <Link href={`/workspace/${workspaceId}/projects`}>
          <Button size="sm" variant="link">
            <span className="text-xs underline">View All</span>
          </Button>
        </Link>
      </div>
      <div className="space-y-2">
        <Form {...form}>
          <div className="">
            <div className="flex items-center justify-between space-x-2">
              <div className="flex items-center space-x-2">
                <div className="flex w-[300px] items-center space-x-2">
                  <Input
                    className="h-8"
                    placeholder="Search projects..."
                    {...register("query")}
                  />
                </div>
                <FacetedFilter
                  onSelectCb={(values) => {
                    setSelectedStatuses(new Set(values));
                  }}
                  options={STATUS_OPTIONS}
                  selectedValues={selectedStatuses}
                  title="Status"
                />
              </div>
              <div className="flex items-center space-x-2">
                {isWorkspaceAdmin && Object.keys(rowSelection).length > 0 && (
                  <ConfirmDeleteProjectsDialog
                    onSuccess={() => {
                      setRowSelection({});
                      refetchProjects();
                    }}
                    projectIds={Object.keys(rowSelection).map(
                      (index) => projects[Number.parseInt(index)].id
                    )}
                    selectedCount={Object.keys(rowSelection).length}
                  />
                )}
                {canModifyProjects && (
                  <CreateProjectDialog
                    onSuccess={() => {
                      queryClient.invalidateQueries({
                        queryKey: [
                          "projects",
                          workspaceId,
                          query,
                          sorting,
                          pageIndex,
                          pageSize,
                        ],
                      });
                      refetchProjects();
                    }}
                    workspaceId={workspaceId}
                  />
                )}
              </div>
            </div>
          </div>
        </Form>
        <div className="overflow-x-auto">
          <div className="table-container">
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
                    <TableCell
                      className="h-24 text-center"
                      colSpan={columns.length}
                    >
                      Loading...
                    </TableCell>
                  </TableRow>
                ) : table.getRowModel().rows?.length ? (
                  table.getRowModel().rows.map((row) => (
                    <TableRow
                      className="cursor-pointer rounded-none!"
                      data-state={row.getIsSelected() && "selected"}
                      key={row.id}
                      onDoubleClick={() => setEditingProject(row.original)}
                    >
                      {row.getVisibleCells().map((cell) => (
                        <TableCell key={cell.id}>
                          {flexRender(
                            cell.column.columnDef.cell,
                            cell.getContext()
                          )}
                        </TableCell>
                      ))}
                    </TableRow>
                  ))
                ) : (
                  <TableRow>
                    <TableCell
                      className="h-24 text-center"
                      colSpan={columns.length}
                    >
                      No projects found.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>

          <div className="">
            <ReactTablePagination
              onPageChange={(page) =>
                setPagination((prev) => ({ ...prev, pageIndex: page - 1 }))
              }
              onPageSizeChange={(size) =>
                setPagination((prev) => ({ ...prev, pageSize: size }))
              }
              page={pageIndex + 1}
              pageSize={pageSize}
              totalItems={totalProjects}
            />
          </div>
        </div>
      </div>

      <EditProjectForm
        canModifyProjects={canModifyProjects}
        isWorkspaceAdmin={isWorkspaceAdmin}
        key={editingProject?.id}
        onClose={() => setEditingProject(null)}
        onSuccess={refetchProjects}
        project={editingProject}
      />
    </div>
  );
}
