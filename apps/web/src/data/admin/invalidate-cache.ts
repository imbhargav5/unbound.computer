import { remoteCache } from "@/typed-cache-tags";

// since the admin is operating, we need to update the cache so (the admin can read the write in a single reqeust)
// but since the public see this in a subsequent request, we need to revalidate the public caches, so the next
export function adminUpdateFeedbackIdCaches(feedbackId: string) {
  remoteCache.admin.feedback.list.updateTag();
  remoteCache.admin.feedback.threads.byId.updateTag({ id: feedbackId });
  remoteCache.admin.feedback.boards.list.updateTag();
  // Invalidate entire feedback branch for bulk board slug invalidation
  remoteCache.admin.feedback.updateTag();
  //
  remoteCache.public.feedback.list.revalidateTag();
  remoteCache.public.feedback.threads.byId.revalidateTag({ id: feedbackId });
  remoteCache.public.feedback.recent.revalidateTag();
  remoteCache.public.feedback.boards.list.revalidateTag();
  // Invalidate entire feedback branch for bulk parameterized cache invalidation
  remoteCache.public.feedback.revalidateTag();
}

export function adminUpdateFeedbackListCaches() {
  remoteCache.admin.feedback.list.updateTag();
  remoteCache.public.feedback.list.revalidateTag();
}

export function adminUpdateRoadmapCache() {
  // Invalidate roadmap caches
  remoteCache.admin.roadmap.items.list.updateTag();
  remoteCache.public.roadmap.items.list.revalidateTag();
}

/**
 * Bulk invalidate ALL feedback thread caches (all IDs).
 * Use this when you need to clear all cached feedback threads, not just a specific one.
 */
export function adminBulkUpdateAllFeedbackThreadCaches() {
  // Update all admin feedback thread caches (immediate)
  // Using hierarchical invalidation - invalidate the branch to clear all entries
  remoteCache.admin.feedback.updateTag();
  // Revalidate all public feedback thread caches (background)
  remoteCache.public.feedback.revalidateTag();
}

/**
 * Bulk invalidate ALL blog post caches (all IDs/slugs).
 * Use this when you need to clear all cached blog posts, not just a specific one.
 */
export function adminBulkUpdateAllBlogCaches() {
  // Update all admin blog caches (immediate)
  remoteCache.admin.blog.updateTag();
  // Revalidate all public blog caches (background)
  remoteCache.public.blog.revalidateTag();
}
