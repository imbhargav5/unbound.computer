'use client';
import { TipTap } from '@/components/tip-tap-Editor/TipTap';
import { T } from '@/components/ui/Typography';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { createBlogPost, updateBlogPost } from '@/data/admin/internal-blog';
import type { DBTable } from '@/types';
import {
  internalBlogPostSchema,
  type InternalBlogPostSchema,
} from '@/utils/zod-schemas/internalBlog';
import { zodResolver } from '@hookform/resolvers/zod';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  Controller,
  useController,
  useForm,
  type Control
} from 'react-hook-form';
import ReactSelect from 'react-select';
import slugify from 'slugify';

import { uploadBlogImage } from '@/data/admin/user';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import type { Editor } from '@tiptap/core';
import { motion } from 'framer-motion';
import { useTheme } from 'next-themes';

const darkThemeStyles = {
  control: (styles) => ({
    ...styles,
    backgroundColor: '#1F2937', // slate-900 from Tailwind's color palette
    borderColor: '#374151', // gray-600 from Tailwind's color palette
    color: '#D1D5DB', // slate-200 from Tailwind's color palette
    '&:hover': {
      borderColor: '#4B5563', // slate-600 from Tailwind's color palette
    },
  }),
  option: (styles, { isFocused, isSelected }) => ({
    ...styles,
    backgroundColor: isSelected
      ? '#374151' // slate-700 from Tailwind's color palette
      : isFocused
        ? '#111827' // slate-950 from Tailwind's color palette
        : '#1F2937', // slate-900 from Tailwind's color palette
    color: '#D1D5DB', // slate-200 from Tailwind's color palette
  }),
  singleValue: (styles) => ({
    ...styles,
    color: '#D1D5DB', // slate-200 from Tailwind's color palette
  }),
  multiValue: (styles) => ({
    ...styles,
    backgroundColor: '#374151', // slate-700 from Tailwind's color palette
  }),
  multiValueLabel: (styles) => ({
    ...styles,
    color: '#D1D5DB', // slate-200 from Tailwind's color palette
  }),
  multiValueRemove: (styles) => ({
    ...styles,
    color: '#D1D5DB', // slate-200 from Tailwind's color palette
    '&:hover': {
      backgroundColor: '#F87171', // red-400 from Tailwind's color palette
      color: '#D1D5DB', // slate-200 from Tailwind's color palette
    },
  }),
  clearIndicator: (styles) => ({
    ...styles,
    color: '#D1D5DB', // slate-200 from Tailwind's color palette
  }),
  menu: (styles) => ({
    ...styles,
    backgroundColor: '#1F2937', // slate-900 from Tailwind's color palette
  }),
};

const defaultContent = {
  type: 'doc',
  content: [
    {
      type: 'paragraph',
      content: [
        {
          type: 'text',
          text: 'Example ',
        },
        {
          type: 'text',
          marks: [
            {
              type: 'bold',
            },
          ],
          text: 'Text',
        },
      ],
    },
  ],
};


const baseDefaultValues: Partial<InternalBlogPostSchema> = {
  status: 'draft',
  is_featured: false,
  title: '',
  slug: '',
  json_content: defaultContent,
  cover_image: "https://images.unsplash.com/photo-1439792675105-701e6a4ab6f0?q=80&w=2073&auto=format&fit=crop&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
  tags: [],
};

type CreateBlogFormProps = {
  mode: 'create';
};

const TipTapWrapper = ({
  control,
}: {
  control: Control<InternalBlogPostSchema>;
}) => {
  const { field: contentField } = useController({
    name: 'content',
    control,
  });



  return (
    <Controller
      control={control}
      name="json_content"
      render={({ field }) => {
        return (
          <TipTap
            value={field.value}
            onChange={(editor: Editor) => {
              // saving json should be enough.
              field.onChange(editor.getJSON());
              // While this is duplicate. We are just trying to minimise
              // breaking changes
              contentField.onChange(editor.getHTML());
            }}
            onBlur={field.onBlur}
          />
        );
      }}
    />
  );
};




export type EditBlogFormProps = {
  mode: 'update';
  initialBlogPost: Partial<InternalBlogPostSchema>;
  postId: string;
};

type BlogFormProps = {
  authors: DBTable<'internal_blog_author_profiles'>[];
  tags: DBTable<'internal_blog_post_tags'>[];
} & (CreateBlogFormProps | EditBlogFormProps);

export const BlogForm = ({ authors, tags, ...rest }: BlogFormProps) => {
  const MotionImage = motion(Image);
  const [isNewCoverImageLoading, setIsNewCoverImageLoading] = useState(false);

  const initialBlogPost = 'initialBlogPost' in rest ? rest.initialBlogPost : {};

  const defaultValues = Object.assign({}, baseDefaultValues, initialBlogPost);

  const router = useRouter();

  const { theme } = useTheme()

  const {
    control,
    handleSubmit,
    register,
    watch,
    setValue,
    formState,
    getValues
  } =
    useForm<InternalBlogPostSchema>({
      resolver: zodResolver(internalBlogPostSchema),
      defaultValues,
    });

  const titleValue = watch('title');
  useEffect(() => {
    const slug = slugify(titleValue, {
      lower: true,
      strict: true,
      replacement: '-',
    });
    setValue('slug', slug);
  }, [setValue, titleValue]);

  const { mutate: createPostMutation, isLoading: isCreatingPost } =
    useSAToastMutation(
      async (data: InternalBlogPostSchema) => {
        const { author_id, tags, ...restPayload } = data;
        if (rest.mode !== 'create') {
          throw new Error('Invalid mode');
        }
        const json_content = JSON.stringify(
          restPayload.json_content instanceof Object ? restPayload.json_content : {}
        );
        const response = await createBlogPost(
          author_id,
          {
            ...restPayload,
            json_content,
          },
          tags.map((tag) => tag.id),
        );
        return response;
      },
      {
        loadingMessage: 'Creating post...',
        successMessage: 'Post created!',
        errorMessage(error) {
          try {
            if (error instanceof Error) {
              return String(error.message);
            }
            return `Failed to create post ${String(error)}`;
          } catch (_err) {
            console.warn(_err);
            return 'Failed to create post';
          }
        },
      },
    );

  const { mutate: upload, isLoading: isUploading } = useSAToastMutation(async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    const response = await uploadBlogImage(formData, file.name);
    return response;
  }, {
    loadingMessage: 'Uploading image...',
    successMessage: 'Image uploaded successfully',
    onSuccess(data) {
      setValue('cover_image', data.status === 'success' ? data.data : "");
    },
    errorMessage(error) {
      try {
        if (error instanceof Error) {
          return String(error.message);
        }
        return `Failed to upload image ${String(error)}`;
      } catch (_err) {
        console.warn(_err);
        return 'Failed to upload image';
      }
    },
  })

  const { mutate: updatePostMutation, isLoading: isUpdatingPost } =
    useSAToastMutation(
      async (data: InternalBlogPostSchema) => {
        const { author_id, tags, ...restPayload } = data;
        if (rest.mode !== 'update') {
          throw new Error('Invalid mode');
        }
        const json_content = JSON.stringify(
          restPayload.json_content instanceof Object ? restPayload.json_content : {}
        );

        const payload = {
          ...restPayload,
          json_content,
        }

        return await updateBlogPost(
          author_id,
          rest.postId,
          payload,
          tags.map((tag) => tag.id),
        );
      },
      {
        loadingMessage: 'Updating post...',
        successMessage: 'Post updated!',
        errorMessage(error) {
          try {
            if (error instanceof Error) {
              return String(error.message);
            }
            return `Failed to update post ${String(error)}`;
          } catch (_err) {
            console.warn(_err);
            return 'Failed to update post';
          }
        },
      }
    );

  function onSubmit(data: InternalBlogPostSchema) {
    if (!data.author_id) {
      data.author_id = undefined;
    }
    if (rest.mode === 'update') {
      updatePostMutation(data);
    } else {
      createPostMutation(data);
    }
  }


  return (
    <div>
      <form
        onSubmit={handleSubmit(onSubmit)}
        className="grid grid-cols-1 xl:grid-cols-6 xl:gap-4"
      >
        <div className='col-span-4 self-start place-self-start'>
          <TipTapWrapper control={control} />
        </div>

        <Card className="p-4 flex h-fit col-span-2 flex-col gap-4">
          <Label>Title</Label>
          <Controller
            control={control}
            name="title"
            render={({ field }) => {
              return <Input {...field} placeholder="Title" />;
            }}
          />
          {formState.errors.title && <T.P className="text-red-500 text-xs">{formState.errors.title.message}</T.P>}
          <T.P className="mt-2">Blog post slug</T.P>
          <Input
            placeholder="this-is-the-blog-post"
            {...register("slug")}
          />
          <div className="flex w-full justify-between">
            <div>
              <T.P>Feature blog post</T.P>
              <T.Small className="text-muted-foreground">
                Highlights your article for increased visibility
              </T.Small>
            </div>

            <Controller
              control={control}
              name="is_featured"
              render={({ field }) => (
                <Switch
                  disabled={isCreatingPost || isUpdatingPost}
                  checked={field.value}
                  onBlur={field.onBlur}
                  name={field.name}
                  ref={field.ref}
                  onCheckedChange={(checked) => field.onChange(checked)}
                />
              )}
            />

          </div>
          <T.P>Cover Image</T.P>
          <Label
            className="inline p-0 m-0 cursor-pointer text-muted-foreground"
            htmlFor="file-input"
          >
            <MotionImage
              animate={{
                opacity: isNewCoverImageLoading ? [0.5, 1, 0.5] : 1,
              }}
              transition={
                /* eslint-disable */
                isNewCoverImageLoading
                  ? {
                    duration: 1,
                    repeat: Number.POSITIVE_INFINITY,
                    repeatType: "reverse",
                  }
                  : undefined
                /* eslint-enable */
              }
              onLoad={(file) => {
                setIsNewCoverImageLoading(false);
              }}
              onError={() => {
                setIsNewCoverImageLoading(false);
              }}
              loading="eager"
              width={800}
              height={600}
              className="h-40 object-center object-cover w-full rounded-lg"
              src={watch('cover_image') ?? "/mockups/laptop.jpeg"}
              alt="avatarUrl"
            />
          </Label>
          <input
            {...register("cover_image")}
            disabled={isNewCoverImageLoading}
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file) {
                upload?.(file);
              }
            }}
            type="file"
            hidden
            name="file-input"
            id="file-input"
            accept="image/*"
          />
          {formState.errors.cover_image && <T.P className="text-red-500 text-xs">{formState.errors.cover_image.message}</T.P>}


          <Label>Summary</Label>
          <Textarea
            {...register("summary")}
            className="resize-none"
            placeholder="A short summary of the blog post"
          />
          {formState.errors.summary && <T.P className="text-red-500 text-xs">{formState.errors.summary.message}</T.P>}

          <Label>Author</Label>
          <Controller
            control={control}
            name="author_id"
            render={({ field }) => (
              <Select value={field.value} onValueChange={field.onChange}>
                <SelectTrigger>
                  <SelectValue placeholder="Select author" />
                </SelectTrigger>
                <SelectContent>
                  {authors.map((admin) => (
                    <SelectItem key={admin.user_id} value={admin.user_id}>
                      {admin.display_name || `User ${admin.user_id}`}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
          />
          {formState.errors.author_id && <T.P className="text-red-500 text-xs">{formState.errors.author_id.message}</T.P>}

          <Label>Tags</Label>
          <Controller
            control={control}
            name="tags"
            render={({ field }) => (
              <ReactSelect
                closeMenuOnSelect={false}
                value={field.value.map((tagId) => ({
                  label: tags.find((tag) => tag.id === tagId.id)?.name ?? '',
                  value: tagId.id,
                }))}
                isMulti
                name={field.name}
                onBlur={field.onBlur}
                onChange={(values) => {
                  if (values.length === 0) {
                    setValue("tags", []);
                    field.onChange([]);
                    return;
                  }
                  let tags = getValues("tags");
                  values.map((value) => {
                    tags = tags.filter((tag) => tag.id !== value.value);
                    tags.push({
                      id: value.value,
                      name: value.label,
                    });
                  });
                  setValue("tags", tags);
                  field.onChange(tags);
                }}
                options={tags.map(tag => ({ label: tag.name, value: tag.id }))}
                styles={theme === 'dark' ? darkThemeStyles : {}} // Apply the dark theme styles only if the current theme is 'dark'
              />
            )}
          />
          {formState.errors.tags && <T.P className="text-red-500 text-xs">{formState.errors.tags.message}</T.P>}
          <div className="flex justify-between mt-8">
            <Button variant={"outline"} type="button" onClick={(e) => {
              e.preventDefault();
              setValue("status", "draft");
              handleSubmit(onSubmit)();
            }}>
              Save as Draft
            </Button>
            <Button type="button" onClick={(e) => {
              e.preventDefault();
              setValue("status", "published");
              handleSubmit(onSubmit)();
            }}>Publish Post</Button>
          </div>
        </Card>
      </form>
    </div>
  );
};
