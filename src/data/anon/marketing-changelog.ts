'use server';
import { supabaseAnonClient } from '@/supabase-clients/anon/supabaseAnonClient';

export async function anonGetAllChangelogItems() {
  const changelogItemsResponse = await supabaseAnonClient
    .from('marketing_changelog')
    .select('*')
    .order('created_at', { ascending: false });

  if (changelogItemsResponse.error) {
    throw changelogItemsResponse.error;
  }

  if (!changelogItemsResponse.data) {
    throw new Error('No data found');
  }

  return changelogItemsResponse.data;
}
