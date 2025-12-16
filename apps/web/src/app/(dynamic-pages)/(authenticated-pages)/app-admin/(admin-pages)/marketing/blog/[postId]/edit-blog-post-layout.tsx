// @/app/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/[postId]/EditBlogPostLayout.tsx

import type React from "react";
import type { DBTable } from "@/types";
import { EditBlogPostForm } from "./edit-blog-post-form";

type EditBlogPostLayoutProps = {
  post: DBTable<"marketing_blog_posts"> & {
    marketing_blog_author_posts?: { author_id: string }[];
    marketing_blog_post_tags_relationship?: { tag_id: string }[];
  };
  authors: DBTable<"marketing_author_profiles">[];
  tags: DBTable<"marketing_tags">[];
};

export const EditBlogPostLayout: React.FC<EditBlogPostLayoutProps> = ({
  post,
  authors,
  tags,
}) => <EditBlogPostForm authors={authors} post={post} tags={tags} />;
