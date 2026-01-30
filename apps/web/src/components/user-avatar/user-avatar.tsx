"use client";
import { useQuery } from "@tanstack/react-query";
import Image from "next/image";
import { getUserAvatarUrlClient } from "@/data/user/client/profile";
import { getQueryClient } from "@/lib/query-client";
import { getPublicUserAvatarUrl } from "@/utils/helpers";

const blurFallback =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAQAAABKfvVzAAAAGklEQVR42mNkMGYgCTCOahjVMKphVANtNQAApZ0E4ZNIscsAAAAASUVORK5CYII=";

const fallbackSource =
  "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp";

export const UserAvatar = ({
  userId,
  size = 24,
}: {
  userId: string;
  size: number;
}) => {
  const queryClient = getQueryClient();
  const { data: avatarUrl } = useQuery(
    {
      queryKey: ["user-avatar-url", userId],
      queryFn: () => getUserAvatarUrlClient(userId),
    },
    queryClient
  );
  let imageSource = fallbackSource;
  if (avatarUrl) {
    imageSource = getPublicUserAvatarUrl(avatarUrl);
  }

  return (
    <Image
      alt={`${userId} avatar`}
      blurDataURL={blurFallback}
      className={"rounded-full"}
      height={size}
      placeholder="blur"
      src={imageSource}
      style={{
        width: size,
        height: size,
      }}
      width={size}
    />
  );
};

export function FallbackImage({ size }: { size: number }) {
  return (
    <Image
      alt={"Fallback"}
      blurDataURL={blurFallback}
      className={"rounded-full"}
      height={size}
      placeholder="blur"
      src={blurFallback}
      style={{
        width: size,
        height: size,
      }}
      width={size}
    />
  );
}
