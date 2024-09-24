'use server';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { Enum } from '@/types';
import moment from 'moment';

export type roadmapDataType = {
  id: string;
  title: string;
  description: string;
  status: Enum<'marketing_feedback_thread_status'>;
  priority: Enum<'marketing_feedback_thread_priority'>;
  tag: Enum<'marketing_feedback_thread_type'>;
  date: string;
};

export const getRoadmap = async () => {
  const roadmapItemsResponse = await supabaseAdminClient
    .from('marketing_feedback_threads')
    .select('*')
    .eq('added_to_roadmap', true)
    .eq('is_publicly_visible', true)
    .is('moderator_hold_category', null)

  if (roadmapItemsResponse.error) {
    throw roadmapItemsResponse.error;
  }

  const roadmapItems = roadmapItemsResponse.data;

  const roadmapArray = roadmapItems.map((item) => {
    return {
      id: item.id,
      title: item.title,
      description: item.content,
      status: item.status,
      priority: item.priority,
      tag: item.type,
      date: moment(item.created_at).format('LL'),
    };
  });
  const plannedCards = roadmapArray.filter((item) => item.status === 'planned');
  const inProgress = roadmapArray.filter(
    (item) => item.status === 'in_progress',
  );
  const completedCards = roadmapArray.filter(
    (item) => item.status === 'completed',
  );

  return {
    plannedCards,
    inProgress,
    completedCards,
  };
};
