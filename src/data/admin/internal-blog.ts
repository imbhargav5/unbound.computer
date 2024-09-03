'use server';
import type { CreateAuthorPayload } from '@/app/(dynamic-pages)/(authenticated-pages)/app_admin/(admin-pages)/blog/(blog-list)/AddAuthorProfileDialog';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import type {
  DBTableInsertPayload,
  DBTableUpdatePayload,
  SAPayload,
} from '@/types';
import { revalidatePath } from 'next/cache';

export const deleteBlogPost = async (
  blogPostId: string,
): Promise<SAPayload> => {
  'use server';

  const { error } = await supabaseAdminClient
    .from('internal_blog_posts')
    .delete()
    .eq('id', blogPostId);

  if (error) {
    return {
      status: 'error',
      message: error.message,
    };
  }
  revalidatePath('/', 'layout');
  return {
    status: 'success',
  };
};

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
    .from('internal_blog_posts')
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
    .from('internal_blog_posts')
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
    .from('internal_blog_author_posts')
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
    .from('internal_blog_author_profiles')
    .select('*')
    .eq('user_id', data.author_id)
    .single();

  return authorData;
};

export const createAuthorProfile = async (
  payload: CreateAuthorPayload,
): Promise<SAPayload> => {
  const { error, data } = await supabaseAdminClient
    .from('internal_blog_author_profiles')
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

export const createBlogPost = async (
  authorId: string | undefined,
  payload: DBTableInsertPayload<'internal_blog_posts'>,
  tagIds: number[],
): Promise<SAPayload> => {
  const { data: slugVerify, error: slugError } = await supabaseAdminClient
    .from('internal_blog_posts')
    .select('*')
    .eq('slug', payload.slug)
    .maybeSingle();

  if (slugError) {
    return {
      status: 'error',
      message: slugError.message,
    };
  }

  if (slugVerify) {
    return {
      status: 'error',
      message: 'Slug already exists',
    };
  }

  const { data, error } = await supabaseAdminClient
    .from('internal_blog_posts')
    .insert(payload)
    .select('*')
    .single();

  if (error) {
    return {
      status: 'error',
      message: error.message,
    };
  }

  if (authorId) {
    // assign to author
    await supabaseAdminClient.from('internal_blog_author_posts').insert({
      author_id: authorId,
      post_id: data.id,
    });
  }

  await updateBlogTagRelationships(data.id, tagIds);
  revalidatePath("/", 'layout');

  return {
    status: 'success',
  };
};

export const getBlogPostById = async (postId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_posts')
    .select(
      '*, internal_blog_author_posts(*, internal_blog_author_profiles(*))',
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
    .from('internal_blog_posts')
    .select(
      '*, internal_blog_author_posts(*, internal_blog_author_profiles(*))',
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
    .from('internal_blog_author_posts')
    .select('*, internal_blog_posts(*)')
    .eq('author_id', authorId);

  if (error) {
    throw error;
  }

  return data;
};

export const getBlogPostTags = async (postId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_post_tags_relationship')
    .select('*')
    .eq('blog_post_id', postId);

  if (error) {
    throw error;
  }

  const tags = await Promise.all(
    data.map(async (tag) => {
      const { data: tagData, error: tagError } = await supabaseAdminClient
        .from('internal_blog_post_tags')
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

export const updateAuthorProfile = async (
  userId: string,
  payload: Partial<DBTableUpdatePayload<'internal_blog_author_profiles'>>,
): Promise<SAPayload> => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_author_profiles')
    .update(payload)
    .eq('user_id', userId)
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

export const updateBlogPost = async (
  authorId: string | undefined,
  postId: string,
  payload: Partial<DBTableUpdatePayload<'internal_blog_posts'>>,
  tagIds: number[],
): Promise<SAPayload> => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_posts')
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
    .from('internal_blog_author_posts')
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
      .from('internal_blog_author_posts')
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
    await assignBlogPostToAuthor(authorId, postId);
  }

  await updateBlogTagRelationships(data.id, tagIds);

  revalidatePath(`/app_admin/blog/post/${data.id}/edit`, 'layout');
  revalidatePath('/app_admin/blog/', 'page');

  return {
    status: 'success',
  };
};

export const assignBlogPostToAuthor = async (
  authorId: string,
  postId: string,
) => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_author_posts')
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
    .from('internal_blog_author_profiles')
    .select('*');

  if (error) {
    throw error;
  }

  return data;
};

export const getAllAppAdmins = async () => {
  const { data: userIds, error } = await supabaseAdminClient
    .from('organization_members')
    .select('*')
    .eq('member_role', 'admin');

  if (error) {
    throw error;
  }

  // get user profiles from user ids
  const { data: userProfiles, error: error2 } = await supabaseAdminClient
    .from('user_profiles')
    .select('*')
    .in(
      'id',
      userIds.map((user) => user.member_id),
    );

  if (error2) {
    throw error2;
  }

  return userProfiles;
};

export const deleteAuthorProfile = async (
  userId: string,
): Promise<SAPayload> => {
  const { error } = await supabaseAdminClient
    .from('internal_blog_author_profiles')
    .delete()
    .eq('user_id', userId);

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

export const createBlogTag = async (
  payload: DBTableInsertPayload<'internal_blog_post_tags'>,
): Promise<SAPayload> => {
  const { error, data } = await supabaseAdminClient
    .from('internal_blog_post_tags')
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

export const updateBlogTag = async (
  id: number,
  payload: Partial<DBTableUpdatePayload<'internal_blog_post_tags'>>,
): Promise<SAPayload> => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_post_tags')
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

export const deleteBlogTag = async (id: number): Promise<SAPayload> => {
  const { error } = await supabaseAdminClient
    .from('internal_blog_post_tags')
    .delete()
    .eq('id', id);

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

export const getAllBlogTags = async () => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_post_tags')
    .select('*');

  if (error) {
    throw error;
  }

  return data;
};

export const getBlogTagRelationships = async (blogPostId: string) => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_post_tags_relationship')
    .select('*')
    .eq('blog_post_id', blogPostId);

  if (error) {
    throw error;
  }

  return data;
};

export const updateBlogTagRelationships = async (
  blogPostId: string,
  tagIds: number[],
) => {
  const { data, error } = await supabaseAdminClient
    .from('internal_blog_post_tags_relationship')
    .delete()
    .eq('blog_post_id', blogPostId);

  if (error) {
    throw error;
  }

  for (const tagId of tagIds) {
    const { error: error2 } = await supabaseAdminClient
      .from('internal_blog_post_tags_relationship')
      .insert({
        blog_post_id: blogPostId,
        tag_id: tagId,
      });

    if (error2) {
      throw error2;
    }
  }
};
