import { z } from "zod";

export const authUserMetadataSchema = z.looseObject({
  onboardingHasAcceptedTerms: z.boolean().default(false),
  onboardingHasCompletedProfile: z.boolean().default(false),
  onboardingHasCreatedWorkspace: z.boolean().default(false),
});

export type AuthUserMetadata = z.infer<typeof authUserMetadataSchema>;
