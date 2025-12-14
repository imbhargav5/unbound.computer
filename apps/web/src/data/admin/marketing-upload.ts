// Client-side upload functions for marketing media
// These use fetch instead of server actions to support large file uploads (>1MB)

import { toSiteURL } from "@/utils/helpers";

export type MediaType = "image" | "video" | "gif";

export interface UploadMediaResult {
  url: string;
  type: MediaType;
}

/**
 * Uploads blog media (images, videos, or GIFs) via the route handler.
 * Supports files up to 100MB for videos, 10MB for images/GIFs.
 */
export async function uploadBlogMedia(
  formData: FormData
): Promise<UploadMediaResult> {
  const response = await fetch(
    toSiteURL("/api/admin/marketing/media?type=blog"),
    {
      method: "POST",
      body: formData,
      credentials: "include",
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || "Upload failed");
  }

  return response.json();
}

/**
 * Uploads changelog media (images, videos, or GIFs) via the route handler.
 * Supports files up to 100MB for videos, 10MB for images/GIFs.
 */
export async function uploadChangelogMedia(
  formData: FormData
): Promise<UploadMediaResult> {
  const response = await fetch(
    toSiteURL("/api/admin/marketing/media?type=changelog"),
    {
      method: "POST",
      body: formData,
      credentials: "include",
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || "Upload failed");
  }

  return response.json();
}
