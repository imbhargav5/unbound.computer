import { z } from 'zod';


export const organizationSlugParamSchema = z.object({
  organizationSlug: z.string(),
});

export const workspaceSlugParamSchema = z.object({
  workspaceSlug: z.string(),
});


export const projectsfilterSchema = z.object({
  page: z.coerce.number().optional(),
  query: z.string().optional(),
});

export const projectParamSchema = z.object({
  projectId: z.string().uuid(),
});


export const projectSlugParamSchema = z.object({
  projectSlug: z.string(),
});

