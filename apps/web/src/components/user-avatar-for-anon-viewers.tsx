"use server";
import Image from "next/image";
import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { anonGetUserProfile } from "@/data/user/elevated-queries";
import { getPublicUserAvatarUrl } from "@/utils/helpers";

const blurFallback =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAQAAABKfvVzAAAAGklEQVR42mNkMGYgCTCOahjVMKphVANtNQAApZ0E4ZNIscsAAAAASUVORK5CYII=";

async function UserAvatarWithFullname({
  userId,
  size,
}: {
  userId: string;
  size: number;
}) {
  const { avatar_url, full_name } = await anonGetUserProfile(userId);

  const userAvatarUrl = getPublicUserAvatarUrl(avatar_url);
  const userFullName = full_name ?? `User ${userId}`;
  return (
    <div className="flex items-center gap-2">
      <div>
        {userAvatarUrl ? (
          <Image
            alt={`${userFullName} avatar`}
            blurDataURL={blurFallback}
            className="rounded-full border shadow-xs"
            data-testid="anon-user-avatar"
            data-user-id={userId}
            height={size}
            placeholder="blur"
            src={userAvatarUrl || ""}
            style={{
              width: size,
              height: size,
            }}
            width={size}
          />
        ) : (
          <div
            className={
              "relative select-none rounded-full border bg-inherit text-sm shadow-xs"
            }
            style={{
              width: size,
              height: size,
            }}
          >
            <span className="absolute top-[50%] left-[50%] -translate-x-1/2 -translate-y-1/2 capitalize">
              {userFullName}
            </span>
          </div>
        )}
      </div>
      <span>{userFullName}</span>
    </div>
  );
}
function UserAvatarWithFullnameFallback({ size }: { size: number }) {
  return (
    <div className="flex items-center space-x-4">
      <Skeleton style={{ width: size, height: size, borderRadius: "100%" }} />
      <Skeleton style={{ width: 80, height: size - 10 }} />
    </div>
  );
}
export async function SuspendedUserAvatarWithFullname({
  userId,
  size,
}: {
  userId: string;
  size: number;
}) {
  return (
    <Suspense fallback={<UserAvatarWithFullnameFallback size={size} />}>
      <UserAvatarWithFullname size={size} userId={userId} />
    </Suspense>
  );
}
