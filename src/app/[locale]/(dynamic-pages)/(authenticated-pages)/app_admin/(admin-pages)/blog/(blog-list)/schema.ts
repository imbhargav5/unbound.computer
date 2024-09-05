import { z } from 'zod';

export const sortSchema = z.enum(['asc', 'desc']).optional();

export type BlogSortSchema = z.infer<typeof sortSchema>;

export const blogFiltersSchema = z
  .object({
    page: z.coerce.number().int().positive().optional(),
    query: z.string().optional(),
  })
  .merge(z.object({ sort: sortSchema }));

export type BlogFiltersSchema = z.infer<typeof blogFiltersSchema>;
