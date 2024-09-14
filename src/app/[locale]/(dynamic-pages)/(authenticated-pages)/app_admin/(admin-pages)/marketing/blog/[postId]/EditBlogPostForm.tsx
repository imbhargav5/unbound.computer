'use client';
import { Tiptap } from "@/components/TipTap";
import { AspectRatio } from "@/components/ui/aspect-ratio";
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { updateBlogPostAction, uploadBlogCoverImageAction } from '@/data/admin/marketing-blog';
import { DBTable } from '@/types';
import { toSafeJSONB } from '@/utils/jsonb';
import { updateMarketingBlogPostSchema } from '@/utils/zod-schemas/marketingBlog';
import { zodResolver } from '@hookform/resolvers/zod';
import { useAction } from 'next-safe-action/hooks';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import React, { useEffect, useRef, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import slugify from "slugify";
import { toast } from 'sonner';
import { z } from 'zod';

type FormData = z.infer<typeof updateMarketingBlogPostSchema>;

type EditBlogPostFormProps = {
  post: DBTable<'marketing_blog_posts'>;
};

export const EditBlogPostForm: React.FC<EditBlogPostFormProps> = ({ post }) => {
  const router = useRouter();
  const toastRef = useRef<string | number>();
  const [coverImageUrl, setCoverImageUrl] = useState(post.cover_image || '');
  const fileInputRef = useRef<HTMLInputElement>(null);

  const { register, handleSubmit, formState: { errors }, control, setValue, watch } = useForm<FormData>({
    resolver: zodResolver(updateMarketingBlogPostSchema),
    defaultValues: {
      ...post,
      json_content: toSafeJSONB(post.json_content),
      seo_data: toSafeJSONB(post.seo_data),
      cover_image: post.cover_image ?? undefined,
    },
  });

  const currentTitle = watch('title');

  useEffect(() => {
    if (currentTitle) {
      setValue('slug', slugify(currentTitle, {
        lower: true,
        strict: true,
        replacement: "-",
      }));
    }
  }, [currentTitle]);

  const updateMutation = useAction(updateBlogPostAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Updating blog post...', { description: 'Please wait while we update the post.' });
    },
    onSuccess: () => {
      toast.success('Blog post updated successfully', {
        description: 'The blog post has been updated successfully.',
        id: toastRef.current
      });
      router.refresh();
    },
    onError: ({ error }) => {
      toast.error(`Failed to update blog post: ${error.serverError || 'Unknown error'}`, {
        description: 'Please try again.',
        id: toastRef.current
      });
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const uploadImageMutation = useAction(uploadBlogCoverImageAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Uploading cover image...', { description: 'Please wait while we upload the image.' });
    },
    onSuccess: ({ data }) => {
      toast.success('Cover image uploaded successfully', {
        description: 'The cover image has been uploaded successfully.',
        id: toastRef.current
      });
      if (data) {
        setCoverImageUrl(data);
        setValue('cover_image', data);
      }
    },
    onError: ({ error }) => {
      toast.error(`Failed to upload cover image: ${error.serverError || 'Unknown error'}`, {
        description: 'Please try again.',
        id: toastRef.current
      });
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const onSubmit = async (data: FormData) => {
    await updateMutation.execute(data);
  };

  const handleImageUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) {
      const formData = new FormData();
      formData.append('file', file);
      await uploadImageMutation.execute({ formData });
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
      <div>
        <Label htmlFor="cover_image">Cover Image</Label>
        <div
          className="mt-2 relative w-full rounded-lg overflow-hidden cursor-pointer"
          onClick={() => fileInputRef.current?.click()}
        >
          <AspectRatio ratio={16 / 9}>
            {coverImageUrl ? (
              <Image
                src={coverImageUrl}
                alt="Cover image"
                fill
                className="object-cover"
              />
            ) : (
              <div className="h-full w-full flex items-center justify-center bg-gray-100">
                <svg className="h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
              </div>
            )}
            <div className="absolute inset-0 bg-black bg-opacity-50 flex items-center justify-center opacity-0 hover:opacity-100 transition-opacity">
              <span className="text-white font-semibold">Change Cover Image</span>
            </div>
          </AspectRatio>
        </div>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={handleImageUpload}
        />

        {errors.cover_image && <p className="text-red-500 text-sm mt-1">{errors.cover_image.message}</p>}
      </div>

      <div>
        <Label htmlFor="title">Title</Label>
        <Input id="title" {...register('title')} />
        {errors.title && <p className="text-red-500 text-sm mt-1">{errors.title.message}</p>}
      </div>
      <div>
        <Label htmlFor="slug">Slug</Label>
        <Input id="slug" {...register('slug')} />
        {errors.slug && <p className="text-red-500 text-sm mt-1">{errors.slug.message}</p>}
      </div>
      <div className="nextbase-editor">
        <Label htmlFor="json_content">Content</Label>
        <Controller
          name="json_content"
          control={control}
          render={({ field }) => (
            <Tiptap
              initialContent={{}}
              onUpdate={({ editor }) => {
                field.onChange(editor.getJSON());
              }}
            />
          )}
        />
      </div>
      <div>
        <Label htmlFor="status">Status</Label>
        <Controller
          name="status"
          control={control}
          render={({ field }) => (
            <Select onValueChange={field.onChange} defaultValue={field.value}>
              <SelectTrigger>
                <SelectValue placeholder="Select status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="draft">Draft</SelectItem>
                <SelectItem value="published">Published</SelectItem>
              </SelectContent>
            </Select>
          )}
        />
        {errors.status && <p className="text-red-500 text-sm mt-1">{errors.status.message}</p>}
      </div>
      <div className="flex items-center space-x-2">
        <Label htmlFor="is_featured">Is Featured</Label>
        <Controller
          name="is_featured"
          control={control}
          render={({ field }) => (
            <div className="flex items-center space-x-2">
              <Switch
                id="is_featured"
                checked={field.value}
                onCheckedChange={field.onChange}
              />
              <span>{field.value ? 'Yes' : 'No'}</span>
            </div>
          )}
        />
      </div>
      <div>
        <Label htmlFor="summary">Summary</Label>
        <Textarea id="summary" {...register('summary')} />
        {errors.summary && <p className="text-red-500 text-sm mt-1">{errors.summary.message}</p>}
      </div>


      <Button type="submit" disabled={updateMutation.status === 'executing'}>
        {updateMutation.status === 'executing' ? 'Updating...' : 'Update Blog Post'}
      </Button>
    </form>
  );
};
