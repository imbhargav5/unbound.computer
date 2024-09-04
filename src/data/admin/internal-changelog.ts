'use server';

import type { ChangelogType } from '@/components/changelog/CreateChangelogForm';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { revalidatePath } from 'next/cache';
import { ensureAppAdmin } from './security';

export const createChangelog = async ({
  title,
  content,
  changelog_image,
}: ChangelogType) => {
  await ensureAppAdmin();


  const { error, data } = await supabaseAdminClient
    .from('marketing_changelog')
    .insert({
      title,
      changes: content,
      cover_image: changelog_image.url,
    });

  if (error) {
    throw error;
  }


  revalidatePath('/changelog', 'page');
  revalidatePath('/app_admin', 'layout');
  if (error) {
    throw error;
  }
  return data;
};
