import { z } from "zod";

// Media type enum for changelog featured media
export const mediaTypeSchema = z.enum(["image", "video", "gif"]);

export const marketingChangelogSchema = z.object({
  id: z.uuid(),
  title: z.string().min(1, "Title is required"),
  json_content: z.record(z.string(), z.unknown()).default({}),
  status: z.enum(["draft", "published"]),
  cover_image: z.string().nullable().optional(),
  created_at: z.string().optional(),
  updated_at: z.string().optional(),
  // New fields for enhanced changelog
  version: z.string().nullable().optional(),
  tags: z.array(z.string()).default([]),
  media_type: mediaTypeSchema.nullable().optional(),
  media_url: z.string().nullable().optional(),
  media_alt: z.string().nullable().optional(),
  media_poster: z.string().nullable().optional(),
  technical_details: z.string().nullable().optional(),
});

export const createMarketingChangelogSchema = marketingChangelogSchema.omit({
  id: true,
  created_at: true,
  updated_at: true,
});

export const createMarketingChangelogActionSchema =
  createMarketingChangelogSchema
    .extend({
      stringified_json_content: z.string(),
    })
    .omit({
      json_content: true,
    });

export const updateMarketingChangelogSchema = marketingChangelogSchema;

export const updateMarketingChangelogFormSchema = z.object({
  id: z.uuid(),
  title: z.string().min(1, "Title is required"),
  json_content: z.record(z.string(), z.unknown()).optional(),
  status: z.enum(["draft", "published"]),
  cover_image: z.string().nullable().optional(),
  created_at: z.string().optional(),
  updated_at: z.string().optional(),
  // New fields for enhanced changelog
  version: z.string().nullable().optional(),
  tags: z.array(z.string()).optional(),
  media_type: mediaTypeSchema.nullable().optional(),
  media_url: z.string().nullable().optional(),
  media_alt: z.string().nullable().optional(),
  media_poster: z.string().nullable().optional(),
  technical_details: z.string().nullable().optional(),
});

export const updateMarketingChangelogActionSchema =
  updateMarketingChangelogSchema
    .extend({
      stringified_json_content: z.string(),
    })
    .omit({
      json_content: true,
    });

export const deleteMarketingChangelogSchema = z.object({
  id: z.uuid(),
});

export const updateChangelogAuthorsSchema = z.object({
  changelogId: z.uuid(),
  authorIds: z.array(z.uuid()),
});
