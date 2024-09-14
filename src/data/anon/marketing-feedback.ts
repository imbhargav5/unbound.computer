'use server';

import { supabaseAnonClient } from '@/supabase-clients/anon/supabaseAnonClient';
import { Enum } from '@/types';


export async function getAnonUserFeedbackList({
  query = '',
  types = [],
  statuses = [],
  priorities = [],
  page = 1,
  limit = 10,
  sort = 'desc',
}: {
  page?: number;
  limit?: number;
  query?: string;
  types?: Array<Enum<'marketing_feedback_thread_type'>>;
  statuses?: Array<Enum<'marketing_feedback_thread_status'>>;
  priorities?: Array<Enum<'marketing_feedback_thread_priority'>>;
  sort?: 'asc' | 'desc';
}) {
  const zeroIndexedPage = page - 1;

  let supabaseQuery = supabaseAnonClient
    .from('marketing_feedback_threads')
    .select('*')
    .or(
      'added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true',
    )
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike('title', `%${query}%`);
  }

  if (types.length > 0) {
    supabaseQuery = supabaseQuery.in('type', types);
  }

  if (statuses.length > 0) {
    supabaseQuery = supabaseQuery.in('status', statuses);
  }

  if (priorities.length > 0) {
    supabaseQuery = supabaseQuery.in('priority', priorities);
  }

  if (sort === 'asc') {
    supabaseQuery = supabaseQuery.order('created_at', { ascending: true });
  } else {
    supabaseQuery = supabaseQuery.order('created_at', { ascending: false });
  }

  const { data, error } = await supabaseQuery;
  if (error) {
    throw error;
  }

  return data;
}

export async function getAnonUserFeedbackTotalPages({
  query = '',
  types = [],
  statuses = [],
  priorities = [],
  page = 1,
  limit = 10,
  sort = 'desc',
}: {
  page?: number;
  limit?: number;
  query?: string;
  types?: Array<Enum<'marketing_feedback_thread_type'>>;
  statuses?: Array<Enum<'marketing_feedback_thread_status'>>;
  priorities?: Array<Enum<'marketing_feedback_thread_priority'>>;
  sort?: 'asc' | 'desc';
}) {
  const zeroIndexedPage = page - 1;

  let supabaseQuery = supabaseAnonClient
    .from('marketing_feedback_threads')
    .select('*', { count: 'exact', head: true })
    .or(
      'added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true',
    )
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike('title', `%${query}%`);
  }

  if (types.length > 0) {
    supabaseQuery = supabaseQuery.in('type', types);
  }

  if (statuses.length > 0) {
    supabaseQuery = supabaseQuery.in('status', statuses);
  }

  if (priorities.length > 0) {
    supabaseQuery = supabaseQuery.in('priority', priorities);
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

  return Math.ceil(count / limit);
}

export async function anonGetRoadmapFeedbackList() {
  const roadmapItemsResponse = await supabaseAnonClient
    .from('marketing_feedback_threads')
    .select('*')
    .eq('added_to_roadmap', true);
  if (roadmapItemsResponse.error) {
    throw roadmapItemsResponse.error;
  }
  if (!roadmapItemsResponse.data) {
    throw new Error('No data found');
  }

  return roadmapItemsResponse.data;
}

async function getRoadmapFeedbackByStatus(
  status: Enum<'marketing_feedback_thread_status'>,
) {
  const roadmapItemsResponse = await supabaseAnonClient
    .from('marketing_feedback_threads')
    .select('*')
    .eq('added_to_roadmap', true)
    .eq('status', status);
  if (roadmapItemsResponse.error) {
    throw roadmapItemsResponse.error;
  }
  if (!roadmapItemsResponse.data) {
    throw new Error('No data found');
  }
  return roadmapItemsResponse.data;
}

export const anonGetPlannedRoadmapFeedbackList = () =>
  getRoadmapFeedbackByStatus('planned');
export const anonGetInProgressRoadmapFeedbackList = () =>
  getRoadmapFeedbackByStatus('in_progress');
export const anonGetCompletedRoadmapFeedbackList = () =>
  getRoadmapFeedbackByStatus('completed');
