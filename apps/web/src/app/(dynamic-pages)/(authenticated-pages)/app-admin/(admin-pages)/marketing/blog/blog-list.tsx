// @/app/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/BlogList.tsx

import { format } from "date-fns";
import { Edit } from "lucide-react";
import type React from "react";
import { Link } from "@/components/intl-link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Typography } from "@/components/ui/typography-ui";
import type { DBTable } from "@/types";
import { CreateBlogPostButton } from "./create-blog-post-button";
import { DeleteBlogPostButton } from "./delete-blog-post-button";

type BlogListProps = {
  posts: DBTable<"marketing_blog_posts">[];
};

export const BlogList: React.FC<BlogListProps> = ({ posts }) => (
  <div className="space-y-6">
    <div className="flex items-center justify-between">
      <Typography.H4>Manage Blog Posts</Typography.H4>
      <CreateBlogPostButton />
    </div>
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Title</TableHead>
          <TableHead>Slug</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Created At</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {posts.map((post) => (
          <TableRow
            data-testid={`admin-blog-list-row-${post.id}`}
            key={post.id}
          >
            <TableCell data-testid={`admin-blog-list-title-${post.id}`}>
              {post.title}
            </TableCell>
            <TableCell>{post.slug}</TableCell>
            <TableCell>
              <Badge
                className="capitalize"
                variant={post.status === "published" ? "default" : "secondary"}
              >
                {post.status}
              </Badge>
            </TableCell>
            <TableCell>
              {format(new Date(post.created_at), "MMM dd, yyyy")}
            </TableCell>
            <TableCell>
              <div className="flex space-x-2">
                <Link href={`/app-admin/marketing/blog/${post.id}`}>
                  <Button size="sm" variant="outline">
                    <Edit className="h-4 w-4" />
                  </Button>
                </Link>
                <DeleteBlogPostButton postId={post.id} postTitle={post.title} />
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </div>
);
