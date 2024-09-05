"use client"
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';

import { Textarea } from '@/components/ui/textarea';
import { adminCreateBlogTagAction } from '@/data/admin/internal-blog';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { Tag } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import slugify from 'slugify';

const blogTagSchema = z.object({
  name: z.string(),
  description: z.string().optional(),
  slug: z.string(),
});

export type BlogTagFormType = z.infer<typeof blogTagSchema>;

export const AddBlogTagDialog = () => {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();
  const { control, handleSubmit, watch, setValue, formState } =
    useForm<BlogTagFormType>({ resolver: zodResolver(blogTagSchema) });


  const { mutate: createBlogTagMutation, isLoading: isCreatingBlogTag } =
    useSAToastMutation(
      async (payload: BlogTagFormType) => await adminCreateBlogTagAction(payload),
      {
        loadingMessage: 'Creating blog tag...',
        successMessage: 'Blog tag created!',
        errorMessage(error, variables) {
          try {
            if (error instanceof Error) {
              return String(error.message);
            }
            return `Failed to create blog tag ${String(error)}`;
          } catch (_err) {
            console.warn(_err);
            return 'Failed to create blog tag';
          }
        },
        onSuccess: () => {
          router.refresh();
          setIsOpen(false);
        },
      },
    );

  const { isValid } = formState;
  const nameValue = watch('name');

  useEffect(() => {
    if (typeof nameValue === 'string') {
      const slug = slugify(nameValue, {
        lower: true,
        strict: true,
        replacement: '-',
      });
      setValue('slug', slug);
    }
  }, [nameValue, setValue]);

  const onSubmit = (data: BlogTagFormType) => {
    console.log(data);
    createBlogTagMutation(data);
  };

  return (
    <Dialog open={isOpen} onOpenChange={(newIsOpen) => setIsOpen(newIsOpen)}>
      <DialogTrigger asChild>
        <Button variant="default" className="w-full">
          Add blog tag
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 rounded-lg">
            <Tag className="w-6 h-6" />
          </div>
          <div className="p-1 mb-4">
            <DialogTitle className="text-lg">Add blog tag</DialogTitle>
            <DialogDescription className="text-base">
              Fill in the details for the new blog tag.
            </DialogDescription>
          </div>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div className="space-y-1">
            <Label>Name</Label>
            <Controller
              control={control}
              name="name"
              render={({ field }) => <Input {...field} placeholder="Name" />}
            />
          </div>
          <div className="space-y-1">
            <Label>Description</Label>
            <Controller
              control={control}
              name="description"
              render={({ field }) => (
                <Textarea {...field} placeholder="Description" />
              )}
            />
          </div>
          <div className="space-y-1">
            <Label>Slug</Label>
            <Controller
              control={control}
              name="slug"
              render={({ field }) => (
                <Input disabled {...field} placeholder="Slug" />
              )}
            />
          </div>
          <DialogFooter className="w-full">
            <Button
              disabled={!isValid || isCreatingBlogTag}
              type="submit"
              className="w-full"
            >
              {isCreatingBlogTag ? 'Submitting...' : 'Submit Tag'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
