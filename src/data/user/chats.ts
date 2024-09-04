'use server';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { createSupabaseUserServerActionClient } from '@/supabase-clients/user/createSupabaseUserServerActionClient';
import { createSupabaseUserServerComponentClient } from '@/supabase-clients/user/createSupabaseUserServerComponentClient';
import type { DBTable, SAPayload, SupabaseFileUploadOptions } from '@/types';
import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import type { Message } from 'ai';
import { nanoid } from 'nanoid';
import slugify from 'slugify';
import urlJoin from 'url-join';

export const insertChatAction = async (
  projectId: string,
  payload: Message[],
  chatId: string,
): Promise<SAPayload<DBTable<'chats'>>> => {
  const supabase = createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUser();

  const { data, error } = await supabase
    .from('chats')
    .upsert(
      {
        id: chatId,
        project_id: projectId,
        user_id: user.id,
        payload: JSON.stringify({ messages: payload }),
      },
      { onConflict: 'id' },
    )
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
    data: data,
  };
};

export const getChatById = async (chatId: string): Promise<DBTable<'chats'>> => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('chats')
    .select('*')
    .eq('id', chatId)
    .single();

  if (error) {
    throw error;
  }

  console.log;

  return data;
};

export const deleteChatAction = async (chatId: string): Promise<void> => {
  const supabase = createSupabaseUserServerActionClient();
  const { error } = await supabase.from('chats').delete().eq('id', chatId);

  if (error) {
    throw error;
  }
};

export const getChats = async (userId: string): Promise<DBTable<'chats'>[]> => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('chats')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return data;
};

export const getChatsHistory = async (
  projectId: string,
  userId: string,
): Promise<DBTable<'chats'>[]> => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('chats')
    .select('*')
    .eq('project_id', projectId)
    .eq('user_id', userId);

  if (error) {
    throw error;
  }

  return data;
};

export const convertAndUploadOpenAiImageAction = async (b64_json: string): Promise<SAPayload<string>> => {
  const byteCharacters = atob(b64_json);
  const byteNumbers = new Array(byteCharacters.length);
  for (let i = 0; i < byteCharacters.length; i++) {
    byteNumbers[i] = byteCharacters.charCodeAt(i);
  }
  const byteArray = new Uint8Array(byteNumbers);

  const file = new File([byteArray], nanoid(), { type: 'image/png' });
  const formData = new FormData();
  formData.append('file', file);

  const response = await uploadOpenAiImageAction(formData, file.name, {
    upsert: true,
  });

  if (response.status === 'error') {
    return {
      status: 'error',
      message: response.message,
    };
  }


  if (response.status === "success") {
    return {
      status: "success",
      data: response.data,
    };
  }

  return {
    status: "error",
    message: "Unknown error",
  };
};

export const uploadOpenAiImageAction = async (
  formData: FormData,
  fileName: string,
  fileOptions?: SupabaseFileUploadOptions | undefined,
): Promise<SAPayload<string>> => {
  "use server";
  const file = formData.get("file");
  if (!file) {
    return {
      status: "error",
      message: "File is empty",
    };
  }
  const slugifiedFilename = slugify(fileName, {
    lower: true,
    strict: true,
    replacement: "-",
  });

  const user = await serverGetLoggedInUser();
  const userId = user.id;
  const userImagesPath = `${userId}/images/${slugifiedFilename}`;

  const { data, error } = await supabaseAdminClient.storage
    .from("openai-images")
    .upload(userImagesPath, file, fileOptions);

  if (error) {
    return {
      status: "error",
      message: error.message,
    };
  }

  const { path } = data;

  const filePath = path.split(",")[0];
  const supabaseFileUrl = urlJoin(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    "/storage/v1/object/public/openai-images",
    filePath,
  );

  return {
    status: "success",
    data: supabaseFileUrl,
  };
};
