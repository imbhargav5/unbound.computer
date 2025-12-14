"use server";
import { cacheLife } from "next/cache";
import { createSupabaseAnonServerClient } from "@/supabase-clients/anon/create-supabase-anon-server-client";
import { supabaseAnonClient } from "@/supabase-clients/anon/supabase-anon-client";
import { remoteCache } from "@/typed-cache-tags";
import type { AppSupabaseClient } from "@/types";

export const anonGetBlogPostById = async (postId: string) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_blog_posts")
    .select(
      "*, marketing_blog_author_posts(*, marketing_blog_author_profiles(*))"
    )
    .eq("id", postId)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetBlogPostBySlug = async (slug: string) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_blog_posts")
    .select("*, marketing_blog_author_posts(*, marketing_author_profiles(*))")
    .eq("slug", slug)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetPublishedBlogPostBySlug = async (slug: string) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_blog_posts")
    .select(
      "*, marketing_blog_author_posts(*, marketing_author_profiles(*)), marketing_blog_post_tags_relationship(*, marketing_tags(*))"
    )
    .eq("slug", slug)
    .eq("status", "published")
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetPublishedBlogPosts = async () => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_blog_posts")
    .select("*, marketing_blog_author_posts(*, marketing_author_profiles(*))")
    .eq("status", "published");

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetPublishedBlogPostsByTagSlug = async (tagSlug: string) => {
  const { data: tag, error: tagError } = await supabaseAnonClient
    .from("marketing_tags")
    .select("*")
    .eq("slug", tagSlug)
    .single();

  if (tagError) {
    throw tagError;
  }

  const {
    data: blogPostTagRelationships,
    error: blogPostTagRelationshipsError,
  } = await supabaseAnonClient
    .from("marketing_blog_post_tags_relationship")
    .select("*")
    .eq("tag_id", tag.id);

  if (blogPostTagRelationshipsError) {
    throw blogPostTagRelationshipsError;
  }

  const postIds = blogPostTagRelationships.map(
    (relationship) => relationship.blog_post_id
  );

  const { data, error } = await supabaseAnonClient
    .from("marketing_blog_posts")
    .select("*, marketing_blog_author_posts(*, marketing_author_profiles(*))")
    .in("id", postIds)
    .eq("status", "published");

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetBlogPostsByAuthorId = async (authorId: string) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_blog_author_posts")
    .select("*, marketing_blog_posts!inner(*)")
    .eq("author_id", authorId)
    .eq("marketing_blog_posts.status", "published");

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetAllBlogPosts = async (
  supabaseClient: AppSupabaseClient
) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_blog_posts")
    .select("*");

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetAllAuthors = async () => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_author_profiles")
    .select("*");

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetOneAuthor = async (userId: string) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_author_profiles")
    .select("*")
    .eq("id", userId);

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetOneAuthorBySlug = async (slug: string) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_author_profiles")
    .select("*")
    .eq("slug", slug)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetTagBySlug = async (slug: string) => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_tags")
    .select("*")
    .eq("slug", slug)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const anonGetAllBlogTags = async () => {
  const { data, error } = await supabaseAnonClient
    .from("marketing_tags")
    .select("*");

  if (error) {
    throw error;
  }

  return data;
};

// ============================================
// Cached functions (from cached-data/anon/marketing-blog.ts)
// ============================================

/**
 * Cached function to get all published blog posts
 * Cache duration: 1 hour (balanced freshness)
 */
export async function cachedGetPublishedBlogPosts() {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.posts.list.cacheTag();

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_blog_posts")
    .select("*, marketing_blog_author_posts(*, marketing_author_profiles(*))")
    .eq("status", "published");

  if (error) {
    throw error;
  }

  return data;
}

export async function cachedGetPublishedBlogPostBySlug(slug: string) {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.posts.bySlug.cacheTag({ slug });

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_blog_posts")
    .select(
      "*, marketing_blog_author_posts(*, marketing_author_profiles(*)), marketing_blog_post_tags_relationship(*, marketing_tags(*))"
    )
    .eq("slug", slug)
    .eq("status", "published")
    .single();

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Cached function to get all blog tags
 * Cache duration: 1 hour
 */
export async function cachedGetAllBlogTags() {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.tags.list.cacheTag();

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase.from("marketing_tags").select("*");

  if (error) {
    throw error;
  }

  return data;
}

export async function cachedGetPublishedBlogPostsByTagSlug(tagSlug: string) {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.posts.byTagSlug.cacheTag({ slug: tagSlug });

  const supabase = await createSupabaseAnonServerClient();

  const { data: tag, error: tagError } = await supabase
    .from("marketing_tags")
    .select("*")
    .eq("slug", tagSlug)
    .single();

  if (tagError) {
    throw tagError;
  }

  const {
    data: blogPostTagRelationships,
    error: blogPostTagRelationshipsError,
  } = await supabase
    .from("marketing_blog_post_tags_relationship")
    .select("*")
    .eq("tag_id", tag.id);

  if (blogPostTagRelationshipsError) {
    throw blogPostTagRelationshipsError;
  }

  const postIds = blogPostTagRelationships.map(
    (relationship) => relationship.blog_post_id
  );

  const { data, error } = await supabase
    .from("marketing_blog_posts")
    .select("*, marketing_blog_author_posts(*, marketing_author_profiles(*))")
    .in("id", postIds)
    .eq("status", "published");

  if (error) {
    throw error;
  }

  return data;
}

export async function cachedGetTagBySlug(slug: string) {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.tags.bySlug.cacheTag({ slug });

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_tags")
    .select("*")
    .eq("slug", slug)
    .single();

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Cached function to get all authors
 * Cache duration: 1 hour
 */
export async function cachedGetAllAuthors() {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.authors.list.cacheTag();

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_author_profiles")
    .select("*");

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Cached function to get one author by slug
 * Uses private cache because slug is a parameter
 */
export async function cachedGetOneAuthorBySlug(slug: string) {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.authors.bySlug.cacheTag({ slug });

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_author_profiles")
    .select("*")
    .eq("slug", slug)
    .single();

  if (error) {
    throw error;
  }

  return data;
}

export async function cachedGetBlogPostsByAuthorId(authorId: string) {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.blog.posts.byAuthorId.cacheTag({ authorId });

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_blog_author_posts")
    .select("*, marketing_blog_posts!inner(*)")
    .eq("author_id", authorId)
    .eq("marketing_blog_posts.status", "published");

  if (error) {
    throw error;
  }

  return data;
}
