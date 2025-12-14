import { Plus } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";

export function CreateBlogPostButton() {
  return (
    <Button asChild data-testid="create-blog-post-button">
      <Link href="/app-admin/marketing/blog/create">
        <Plus className="mr-2 h-4 w-4" />
        Create Blog Post
      </Link>
    </Button>
  );
}
