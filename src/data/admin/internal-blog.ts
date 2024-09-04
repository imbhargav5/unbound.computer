'use server';
import { Json } from '@/lib/database.types';
import { adminActionClient } from '@/lib/safe-action';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import type {
  DBTableInsertPayload,
  DBTableUpdatePayload,
  SAPayload,
} from '@/types';
import { marketingAuthorProfileFormSchema, marketingBlogPostFormSchema } from '@/utils/zod-schemas/internalBlog';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';

const deleteBlogPostSchema = z.object({
  blogPostId: z.string().uuid()
});

export const adminDeleteBlogPostAction = adminActionClient
  .schema(deleteBlogPostSchema)
  .action(async ({ parsedInput: { blogPostId } }) => {
    const { error } = await supabaseAdminClient
      .from('marketing_blog_posts')
      .delete()
      .eq('id', blogPostId);

    if (error) {
      throw new Error(error.message);
    }

    revalidatePath('/', 'layout');
  });

export const getAllBlogPosts = async ({
  query = '',
  keywords = [],
  page = 1,
  limit = 5,
  sort = 'desc',
  status = undefined
}: {
  query?: string;
  keywords?: string[];
  page?: number;
  limit?: number;
  sort?: 'asc' | 'desc';
  status?: 'draft' | 'published';
}) => {
  const zeroIndexedPage = page - 1;

  let supabaseQuery = supabaseAdminClient
    .from('marketing_blog_posts')
    .select('*')
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike('title', `%${query}%`);
  }

  if (sort === 'asc') {
    supabaseQuery = supabaseQuery.order('created_at', { ascending: true });

  } else {
    supabaseQuery = supabaseQuery.order('created_at', { ascending: false });
  }

  if (status) {
    supabaseQuery = supabaseQuery.eq('status', status);
  }

  const { data, error } = await supabaseQuery;

  if (error) {
    throw error;
  }

  let dataFormatted = await Promise.all(
    data.map(async (post) => {
      const author = await getAuthor(post.id);
      const tags = await getBlogPostTags(post.id);

      return {
        ...post,
        author,
        tags,
      };
    }),
  );

  if (keywords.length > 0) {
    dataFormatted = dataFormatted.filter((post) =>
      keywords.some((keyword) =>
        post.tags.map((tag) => tag.name).includes(keyword),
      ),
    );
  }

  return dataFormatted;
};

export async function getBlogPostsTotalPages({
  query = '',
  page = 1,
  limit = 5,
  sort = 'desc',
}: {
  page?: number;
  limit?: number;
  query?: string;
  sort?: 'asc' | 'desc';
}) {
  const zeroIndexedPage = page - 1;
  let supabaseQuery = supabaseAdminClient
    .from('marketing_blog_posts')
    .select('id', { count: 'exact', head: true })
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike('title', `%${query}%`);
  }
  if (sort === 'asc') {
    supabaseQuery = supabaseQuery.order('created_at', { ascending: true });
  } else {
    supabaseQuery = supabaseQuery.order('created_at', { ascending: false });
  }

  const { count, error } = await supabaseQuery;

  if (error) {
    throw error;
  }

  if (!count) {
    return 0;
  }

  return Math.ceil(count / limit) ?? 0;
}

export const getAuthor = async (postId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_author_posts')
    .select('*')
    .eq('post_id', postId)
    .maybeSingle();

  if (error) {
    console.log('error', error);
    throw error;
  }
  if (!data) {
    return null;
  }

  const { data: authorData } = await supabaseAdminClient
    .from('marketing_author_profiles')
    .select('*')
    .eq('user_id', data.author_id)
    .single();

  return authorData;
};

export const adminCreateAuthorProfileAction = adminActionClient
  .schema(marketingAuthorProfileFormSchema)
  .action(async ({ parsedInput }) => {
    const { error, data } = await supabaseAdminClient
      .from('marketing_author_profiles')
      .insert(parsedInput);

    if (error) {
      throw new Error(error.message);
    }

    return data;
  });

export const adminCreateBlogPostAction = adminActionClient
  .schema(marketingBlogPostFormSchema)
  .action(async ({ parsedInput: payload }) => {
    const { data, error } = await supabaseAdminClient
      .from('marketing_blog_posts')
      .insert({
        ...payload,
        json_content: payload.json_content as Json,
      })
      .select('*')
      .single();

    if (error) {
      throw new Error(error.message);
    }

    revalidatePath("/", 'layout');

    return data;
  });

export const getBlogPostById = async (postId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_posts')
    .select(
      '*, marketing_blog_author_posts(*, marketing_author_profiles(*))',
    )
    .eq('id', postId)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const getBlogPostBySlug = async (slug: string) => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_posts')
    .select(
      '*, marketing_blog_author_posts(*, marketing_author_profiles(*))',
    )
    .eq('slug', slug)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const getBlogPostsByAuthorId = async (authorId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_author_posts')
    .select('*, marketing_blog_posts(*)')
    .eq('author_id', authorId);

  if (error) {
    throw error;
  }

  return data;
};

export const getBlogPostTags = async (postId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_post_tags_relationship')
    .select('*')
    .eq('blog_post_id', postId);

  if (error) {
    throw error;
  }

  const tags = await Promise.all(
    data.map(async (tag) => {
      const { data: tagData, error: tagError } = await supabaseAdminClient
        .from('marketing_tags')
        .select('*')
        .eq('id', tag.tag_id)
        .single();

      if (tagError) {
        throw tagError;
      }

      return tagData ?? [];
    }),
  );

  return tags;
};

const updateAuthorProfileSchema = z.object({
  authorId: z.string().uuid(),
  payload: marketingAuthorProfileFormSchema.partial(),
});

export const adminUpdateAuthorProfileAction = adminActionClient
  .schema(updateAuthorProfileSchema)
  .action(async ({ parsedInput: { authorId, payload } }) => {
    const { data, error } = await supabaseAdminClient
      .from('marketing_author_profiles')
      .update(payload)
      .eq('id', authorId)
      .select('*')
      .single();

    if (error) {
      throw new Error(error.message);
    }

    return data;
  });

export const adminUpdateBlogPostAction = async (
  authorId: string | undefined,
  postId: string,
  payload: Partial<DBTableUpdatePayload<'marketing_blog_posts'>>,
  tagIds: string[],
): Promise<SAPayload> => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_posts')
    .update(payload)
    .eq('id', postId)
    .select('*')
    .single();

  if (error) {
    return {
      status: 'error',
      message: error.message,
    };
  }

  const { data: oldAuthors, error: oldAuthorsError } = await supabaseAdminClient
    .from('marketing_blog_author_posts')
    .select('*')
    .eq('post_id', postId);

  if (oldAuthorsError) {
    return {
      status: 'error',
      message: oldAuthorsError.message,
    };
  }

  for (const oldAuthor of oldAuthors) {
    const { error: deleteError } = await supabaseAdminClient
      .from('marketing_blog_author_posts')
      .delete()
      .eq('author_id', oldAuthor.author_id)
      .eq('post_id', postId);

    if (deleteError) {
      return {
        status: 'error',
        message: deleteError.message,
      };
    }
  }

  // assign new author to the post
  if (authorId) {
    await adminAssignBlogPostToAuthorAction(authorId, postId);
  }

  await updateBlogTagRelationshipsAction(data.id, tagIds);

  revalidatePath(`/app_admin/blog/post/${data.id}/edit`, 'layout');
  revalidatePath('/app_admin/blog/', 'page');

  return {
    status: 'success',
  };
};

export const adminAssignBlogPostToAuthorAction = async (
  authorId: string,
  postId: string,
) => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_author_posts')
    .insert({
      author_id: authorId,
      post_id: postId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const getAllAuthors = async () => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_author_profiles')
    .select('*');

  if (error) {
    throw error;
  }

  return data;
};



const deleteAuthorProfileSchema = z.object({
  authorId: z.string().uuid()
});

export const adminDeleteAuthorProfileAction = adminActionClient
  .schema(deleteAuthorProfileSchema)
  .action(async ({ parsedInput: { authorId } }) => {
    const { error } = await supabaseAdminClient
      .from('marketing_author_profiles')
      .delete()
      .eq('id', authorId);

    if (error) {
      throw new Error(error.message);
    }

    // No need to return anything if the operation is successful
  });

export const adminCreateBlogTagAction = async (
  payload: DBTableInsertPayload<'marketing_tags'>,
): Promise<SAPayload> => {
  const { error, data } = await supabaseAdminClient
    .from('marketing_tags')
    .insert(payload);

  if (error) {
    return {
      status: 'error',
      message: error.message,
    };
  }

  return {
    status: 'success',
  };
};

export const adminUpdateBlogTagAction = async (
  id: number,
  payload: Partial<DBTableUpdatePayload<'marketing_tags'>>,
): Promise<SAPayload> => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_tags')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single();

  if (error) {
    return {
      status: 'error',
      message: error.message,
    };
  }

  return {
    status: 'success',
  };
};

const deleteBlogTagSchema = z.object({
  id: z.string().uuid()
});

export const adminDeleteBlogTagAction = adminActionClient
  .schema(deleteBlogTagSchema)
  .action(async ({ parsedInput: { id } }) => {
    const { error } = await supabaseAdminClient
      .from('marketing_tags')
      .delete()
      .eq('id', id);

    if (error) {
      throw new Error(error.message);
    }

    // No need to return anything if the operation is successful
  });
export const getAllBlogTags = async () => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_tags')
    .select('*');

  if (error) {
    throw error;
  }

  return data;
};

export const getBlogTagRelationships = async (blogPostId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_post_tags_relationship')
    .select('*')
    .eq('blog_post_id', blogPostId);

  if (error) {
    throw error;
  }

  return data;
};

const updateBlogTagRelationshipsSchema = z.object({
  blogPostId: z.string().uuid(),
  tagIds: z.array(z.string().uuid()),
});

export const updateBlogTagRelationshipsAction = adminActionClient
  .schema(updateBlogTagRelationshipsSchema)
  .action(async ({ parsedInput: { blogPostId, tagIds } }) => {
    const { error: deleteError } = await supabaseAdminClient
      .from('marketing_blog_post_tags_relationship')
      .delete()
      .eq('blog_post_id', blogPostId);

    if (deleteError) {
      throw new Error(deleteError.message);
    }

    for (const tagId of tagIds) {
      const { error: insertError } = await supabaseAdminClient
        .from('marketing_blog_post_tags_relationship')
        .insert({
          blog_post_id: blogPostId,
          tag_id: tagId,
        });

      if (insertError) {
        throw new Error(insertError.message);
      }
    }

    // No need to return anything if the operation is successful
  });
