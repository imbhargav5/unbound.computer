import { z } from "zod";

export const generateImageSchema = z.object({
  prompt: z.string(),
  size: z.enum(["256x256", "512x512", "1024x1024"]),
  n: z.number().int().positive().max(10).default(1),
});

export const generateImageFormSchema = z.object({
  prompt: z.string(),
  size: z.enum(["256x256", "512x512", "1024x1024"]),
  n: z.number().int().positive().max(10).optional(),
});

export type GenerateImageSchemaType = z.infer<typeof generateImageSchema>;
export type GenerateImageFormSchemaType = z.infer<
  typeof generateImageFormSchema
>;
