"use server";
import { renderAsync } from "@react-email/render";
import ConfirmAccountDeletionEmail from "emails/account-deletion-request";
import slugify from "slugify";
import urlJoin from "url-join";
import { z } from "zod";
import { PRODUCT_NAME } from "@/constants";
import { authActionClient } from "@/lib/safe-action";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { userPrivateCache } from "@/typed-cache-tags";
import type { SupabaseFileUploadOptions } from "@/types";
import { sendEmail } from "@/utils/api-routes/utils";
import { toSiteURL } from "@/utils/helpers";
import { isSupabaseUserClaimAppAdmin } from "@/utils/is-supabase-user-app-admin";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import type { AuthUserMetadata } from "@/utils/zod-schemas/auth-user-metadata";
import { refreshSessionAction } from "./session";

export async function getIsAppAdmin(): Promise<boolean> {
  const user = await serverGetLoggedInUserClaims();
  return isSupabaseUserClaimAppAdmin(user);
}

export async function getUserProfile(userId: string) {
  "use cache: private";
  userPrivateCache.userPrivate.myProfile.detail.cacheTag();

  const supabase = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from("user_profiles")
    .select("*")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data;
}

export const getUserFullName = async (userId: string) => {
  "use cache: private";
  userPrivateCache.userPrivate.myProfile.fullName.cacheTag();

  const supabase = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from("user_profiles")
    .select("full_name")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data.full_name;
};

export const getUserAvatarUrl = async (userId: string) => {
  "use cache: private";
  userPrivateCache.userPrivate.myProfile.avatarUrl.cacheTag();

  const supabase = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from("user_profiles")
    .select("avatar_url")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data.avatar_url;
};

export const uploadPublicUserAvatar = async (
  formData: FormData,
  fileName: string,
  fileOptions?: SupabaseFileUploadOptions | undefined
): Promise<string> => {
  const file = formData.get("file");
  if (!file) {
    throw new Error("File is empty");
  }
  const slugifiedFilename = slugify(fileName, {
    lower: true,
    strict: true,
    replacement: "-",
  });
  const supabaseClient = await createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUserClaims();
  const userId = user.sub;
  const userImagesPath = `${userId}/images/${slugifiedFilename}`;

  const { data, error } = await supabaseClient.storage
    .from("public-user-assets")
    .upload(userImagesPath, file, fileOptions);

  if (error) {
    throw new Error(error.message);
  }

  const { path } = data;

  const filePath = path.split(",")[0];
  const supabaseFileUrl = urlJoin(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    "/storage/v1/object/public/public-user-assets",
    filePath
  );

  return supabaseFileUrl;
};

const uploadPublicUserAvatarSchema = z.object({
  formData: z.instanceof(FormData),
  fileName: z.string(),
  fileOptions: z
    .object({
      cacheControl: z.string().optional(),
      upsert: z.boolean().optional(),
      contentType: z.string().optional(),
    })
    .optional()
    .default({}),
});

export const uploadPublicUserAvatarAction = authActionClient
  .inputSchema(uploadPublicUserAvatarSchema)
  .action(
    async ({
      parsedInput: { formData, fileName, fileOptions },
    }): Promise<string> => {
      const profilePictureURL = await uploadPublicUserAvatar(
        formData,
        fileName,
        fileOptions
      );

      const actionResponse = await updateProfilePictureUrlAction({
        profilePictureUrl: profilePictureURL,
      });

      if (actionResponse?.data) {
        return actionResponse.data;
      }

      console.log("actionResponse", actionResponse);
      throw new Error("Updating profile picture url failed");
    }
  );

const updateProfilePictureUrlSchema = z.object({
  profilePictureUrl: z.string(),
});

export const updateProfilePictureUrlAction = authActionClient
  .inputSchema(updateProfilePictureUrlSchema)
  .action(async ({ parsedInput: { profilePictureUrl } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();
    const user = await serverGetLoggedInUserClaims();
    const { error } = await supabaseClient
      .from("user_profiles")
      .update({
        avatar_url: profilePictureUrl,
      })
      .eq("id", user.sub);

    if (error) {
      throw new Error(error.message);
    }

    userPrivateCache.userPrivate.myProfile.avatarUrl.updateTag();
    return profilePictureUrl;
  });

const updateUserProfileNameAndAvatarSchema = z.object({
  fullName: z.string(),
  avatarUrl: z.string().optional(),
  isOnboardingFlow: z.boolean().default(false),
});

export const updateUserProfileNameAndAvatarAction = authActionClient
  .inputSchema(updateUserProfileNameAndAvatarSchema)
  .action(
    async ({ parsedInput: { fullName, avatarUrl, isOnboardingFlow } }) => {
      const supabaseClient = await createSupabaseUserServerActionClient();
      const user = await serverGetLoggedInUserClaims();
      const { data, error } = await supabaseClient
        .from("user_profiles")
        .update({
          full_name: fullName,
          avatar_url: avatarUrl,
        })
        .eq("id", user.sub)
        .select()
        .single();

      if (error) {
        throw new Error(error.message);
      }

      if (isOnboardingFlow) {
        const updateUserMetadataPayload: Partial<AuthUserMetadata> = {
          onboardingHasCompletedProfile: true,
        };

        const updateUserMetadataResponse = await supabaseClient.auth.updateUser(
          {
            data: updateUserMetadataPayload,
          }
        );

        if (updateUserMetadataResponse.error) {
          throw new Error(updateUserMetadataResponse.error.message);
        }

        await refreshSessionAction();
      }

      userPrivateCache.userPrivate.myProfile.updateTag();
      return data;
    }
  );

const updateUserProfilePictureSchema = z.object({
  avatarUrl: z.string(),
});

export const updateUserProfilePictureAction = authActionClient
  .inputSchema(updateUserProfilePictureSchema)
  .action(async ({ parsedInput: { avatarUrl } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();
    const user = await serverGetLoggedInUserClaims();
    const { data, error } = await supabaseClient
      .from("user_profiles")
      .update({
        avatar_url: avatarUrl,
      })
      .eq("id", user.sub)
      .select()
      .single();

    if (error) {
      throw new Error(error.message);
    }

    userPrivateCache.userPrivate.myProfile.avatarUrl.updateTag();
    return data;
  });

export async function acceptTermsOfService(): Promise<boolean> {
  const supabaseClient = await createSupabaseUserServerActionClient();

  const updateUserMetadataPayload: Partial<AuthUserMetadata> = {
    onboardingHasAcceptedTerms: true,
  };

  const { error } = await supabaseClient.auth.updateUser({
    data: updateUserMetadataPayload,
  });

  if (error) {
    throw new Error(`Failed to accept terms of service: ${error.message}`);
  }

  await refreshSessionAction();

  return true;
}

export const acceptTermsOfServiceAction = authActionClient.action(
  async (): Promise<boolean> => await acceptTermsOfService()
);

// Define the action to request account deletion
export const requestAccountDeletionAction = authActionClient.action(
  async () => {
    const supabaseClient = await createSupabaseUserServerActionClient();
    const user = await serverGetLoggedInUserClaims();

    if (!user.email) {
      throw new Error("User email not found");
    }

    const { data, error } = await supabaseClient
      .from("account_delete_tokens")
      .upsert({
        user_id: user.sub,
      })
      .select("*")
      .single();

    if (error) {
      throw new Error(error.message);
    }

    const userFullName =
      (await getUserFullName(user.sub)) ?? `User ${user.email ?? ""}`;

    const deletionHTML = await renderAsync(
      <ConfirmAccountDeletionEmail
        appName={PRODUCT_NAME}
        deletionConfirmationLink={toSiteURL(
          `/confirm-delete-user/${data.token}`
        )}
        userName={userFullName}
      />
    );

    await sendEmail({
      from: process.env.ADMIN_EMAIL,
      html: deletionHTML,
      subject: `Confirm Account Deletion - ${PRODUCT_NAME}`,
      to: user.email,
    });

    return data;
  }
);

const updateUserFullNameSchema = z.object({
  fullName: z.string().min(1, "Full name is required"),
  isOnboardingFlow: z.boolean().default(false),
});

export const updateUserFullNameAction = authActionClient
  .inputSchema(updateUserFullNameSchema)
  .action(async ({ parsedInput: { fullName, isOnboardingFlow } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();
    const user = await serverGetLoggedInUserClaims();

    const { data, error } = await supabaseClient
      .from("user_profiles")
      .update({ full_name: fullName })
      .eq("id", user.sub)
      .select()
      .single();

    if (error) {
      throw new Error(`Failed to update full name: ${error.message}`);
    }

    if (isOnboardingFlow) {
      const updateUserMetadataPayload: Partial<AuthUserMetadata> = {
        onboardingHasCompletedProfile: true,
      };

      const updateUserMetadataResponse = await supabaseClient.auth.updateUser({
        data: updateUserMetadataPayload,
      });

      if (updateUserMetadataResponse.error) {
        throw new Error(updateUserMetadataResponse.error.message);
      }

      await refreshSessionAction();
    }

    userPrivateCache.userPrivate.myProfile.fullName.updateTag();
    return data;
  });
