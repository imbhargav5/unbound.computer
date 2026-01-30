import { z } from "zod";

export const organizationSlugParamSchema = z.object({
  organizationSlug: z.string(),
});
