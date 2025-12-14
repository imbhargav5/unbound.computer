import { z } from "zod";
import { authUserMetadataSchema } from "./auth-user-metadata";

const userMetadataSchema = authUserMetadataSchema.extend({
  email: z.email().nullish(),
  email_verified: z.boolean().nullish(),
  phone_verified: z.boolean().nullish(),
  sub: z.string().nullish(),
});

export const userClaimsSchema = z.looseObject({
  iss: z.string(),
  sub: z.string(),
  aud: z.string().or(z.array(z.string())),
  exp: z.number(),
  iat: z.number(),
  role: z.string(),
  aal: z.unknown(),
  session_id: z.string(),
  email: z.email(),
  is_anonymous: z.boolean(),
  user_metadata: userMetadataSchema,
  app_metadata: z.looseObject({}),
});

export type UserClaimsSchemaType = z.infer<typeof userClaimsSchema>;
