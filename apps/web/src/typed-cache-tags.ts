import { createCache } from "next-cool-cache";

/**
 * Cache schema defining all cacheable resources in the application.
 *
 * Structure:
 * - data: Server-side data caches
 * - components: Component-level caches for React Server Components
 *
 * Each leaf node can be:
 * - {} for resources without parameters
 * - { _params: ['paramName'] as const } for parameterized resources
 */
const commonDataSchema = {
  feedback: {
    list: {},
    recent: {},
    threads: {
      byId: { _params: ["id"] as const },
      byBoardId: { _params: ["boardId"] as const },
      byBoardSlug: { _params: ["slug"] as const },
    },
    boards: {
      list: {},
      byId: { _params: ["id"] as const },
      bySlug: { _params: ["slug"] as const },
    },
    comments: {
      byThreadId: {
        list: { _params: ["threadId"] as const },
        count: { _params: ["threadId"] as const },
      },
    },
    reactions: {
      byThreadId: {
        list: { _params: ["threadId"] as const },
        count: { _params: ["threadId"] as const },
      },
    },
  },
  blog: {
    posts: {
      list: {},
      byId: { _params: ["id"] as const },
      bySlug: { _params: ["slug"] as const },
      byTagSlug: { _params: ["slug"] as const },
      byAuthorId: { _params: ["authorId"] as const },
      byAuthorSlug: { _params: ["slug"] as const },
    },
    tags: {
      list: {},
      byId: { _params: ["id"] as const },
      bySlug: { _params: ["slug"] as const },
    },
    authors: {
      list: {},
      byId: { _params: ["id"] as const },
      bySlug: { _params: ["slug"] as const },
    },
  },
  changelog: {
    items: {
      list: {},
      byId: { _params: ["id"] as const },
    },
  },
  roadmap: {
    items: {
      list: {},
      byId: { _params: ["id"] as const },
    },
    feedback: {
      items: {
        list: {},
        byId: { _params: ["id"] as const },
      },
    },
    components: {
      list: {},
      byId: { _params: ["id"] as const },
    },
  },
  user: {
    profile: {
      detail: {
        byId: { _params: ["id"] as const },
      },
      avatarUrl: {
        byId: { _params: ["id"] as const },
      },
      fullName: {
        byId: { _params: ["id"] as const },
      },
    },
  },
} as const;

/**
 * Cache scopes for different user contexts:
 * - admin: Internal admin data (all resources regardless of visibility)
 * - public: Public/published resources (visible to anonymous users)
 * - userPrivate: User-specific private data (requires authentication)
 */
const commonDataScopes = ["admin", "public"] as const;

/**
 * Type-safe cache instance created from the schema and scopes.
 *
 * Usage patterns:
 *
 * In cached functions:
 * ```
 * "use cache: remote";
 * cache.public.data.blog.postBySlug.cacheTag({ slug });
 * ```
 *
 * After data mutations:
 * ```
 * // Admin gets immediate update
 * cache.admin.data.blog.postBySlug.updateTag({ slug });
 * // Public gets stale-while-revalidate
 * cache.public.data.blog.postBySlug.revalidateTag({ slug });
 * ```
 *
 * Hierarchical invalidation:
 * ```
 * // Invalidate all blog data for admin
 * cache.admin.data.blog.revalidateTag();
 * ```
 */
export const remoteCache = createCache(commonDataSchema, commonDataScopes);

// For the user
// we want to cache the profile details
const userPrivateDataSchema = {
  user: {
    _params: ["userId"] as const,
    myProfile: {
      detail: {},
      fullName: {},
      email: {},
      avatarUrl: {},
    },
  },
} as const;

const userPrivateDataScopes = ["userPrivate"] as const;

export const userPrivateCache = createCache(
  userPrivateDataSchema,
  userPrivateDataScopes
);
