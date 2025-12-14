import type { SortingState } from "@tanstack/react-table";
import { z } from "zod";
import { projectStatusEnum } from "./enums/project-status-enum";

export const projectsFilterSchema = z.object({
  query: z.string().default(""),
  page: z.number().default(1),
  perPage: z.number().default(10),
  sorting: z.custom<SortingState>().default([]),
  statuses: z.array(projectStatusEnum).default([]),
});

export const projectsFilterFormSchema = z.object({
  query: z.string().optional(),
  page: z.number().optional(),
  perPage: z.number().optional(),
  sorting: z.custom<SortingState>().optional(),
  statuses: z.array(projectStatusEnum).optional(),
});

export type ProjectsFilterSchema = z.infer<typeof projectsFilterSchema>;
export type ProjectsFilterFormSchema = z.infer<typeof projectsFilterFormSchema>;
