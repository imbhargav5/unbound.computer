import type { SortingState } from "@tanstack/react-table";
import { z } from "zod";

export const projectsFilterSchema = z.object({
  query: z.string().optional().default(""),
  page: z.number().optional().default(1),
  perPage: z.number().optional().default(10),
  sorting: z.custom<SortingState>().optional().default([]),
});

export type ProjectsFilterSchema = z.infer<typeof projectsFilterSchema>;
