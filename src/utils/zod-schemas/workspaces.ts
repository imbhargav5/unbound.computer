import { RESTRICTED_SLUG_NAMES, SLUG_PATTERN } from "@/constants";
import { z } from "zod";

export const createWorkspaceSchema = z.object({
  name: z.string().min(1, "Name is required"),
  slug: z
    .string()
    .refine(
      (slug) =>
        !RESTRICTED_SLUG_NAMES.includes(slug) && SLUG_PATTERN.test(slug),
      {
        message: "Invalid or restricted slug",
      },
    )
    .optional(),
  workspaceType: z.enum(["solo", "team"]).default("solo"),
  isOnboardingFlow: z.boolean().optional().default(false),
});

export type CreateWorkspaceSchema = z.infer<typeof createWorkspaceSchema>;
