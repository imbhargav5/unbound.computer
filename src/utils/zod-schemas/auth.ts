import { z } from "zod";
import { socialProviders } from "./social-providers";

export const signUpWithPasswordSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  next: z.string().nullish().optional(),
});

export type SignUpWithPasswordSchemaType = z.infer<typeof signUpWithPasswordSchema>;

export const signInWithMagicLinkSchema = z.object({
  email: z.string().email(),
  next: z.string().nullish().optional(),
  shouldCreateUser: z.boolean().optional().default(false),
});

export type signInWithMagicLinkSchemaType = z.infer<typeof signInWithMagicLinkSchema>;

export const signInWithProviderSchema = z.object({
  provider: socialProviders,
  next: z.string().nullish().optional(),
});

export type SignInWithProviderSchemaType = z.infer<typeof signInWithProviderSchema>;

export const resetPasswordSchema = z.object({
  email: z.string().email(),
});

export type ResetPasswordSchemaType = z.infer<typeof resetPasswordSchema>;


export const signInWithPasswordSchema = z.object({
  email: z.string().email(),
  password: z.string(),
  next: z.string().nullish().optional(),
});

export type SignInWithPasswordSchemaType = z.infer<typeof signInWithPasswordSchema>;
