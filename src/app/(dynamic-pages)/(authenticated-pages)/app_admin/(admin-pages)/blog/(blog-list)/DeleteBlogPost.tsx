'use client';
import { Button } from '@/components/ui/button';
import { adminDeleteBlogPostAction } from '@/data/admin/internal-blog';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { Trash2 } from 'lucide-react';

export function DeleteBlogPost({ blogPostId }: { blogPostId: string }) {
  const { mutate, isLoading } = useSAToastMutation(
    async () => {
      return adminDeleteBlogPostAction(blogPostId);
    },
    {
      loadingMessage: 'Deleting blog post...',
      successMessage: 'Blog post deleted!',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to delete blog post ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to delete blog post';
        }
      },
    },
  );

  return (
    <Button
      type="button"
      onClick={() => {
        mutate();
      }}
      size="icon"
      variant="ghost"
      aria-disabled={isLoading}
    >
      <Trash2 className="h-6 w-6" />
    </Button>
  );
}
