"use client";

import { useQuery } from "@tanstack/react-query";
import { T } from "@/components/ui/typography-ui";
import { getUserFullNameClient } from "@/data/user/client/profile";
import { getQueryClient } from "@/lib/query-client";

export const UserFullName = ({ userId }: { userId: string }) => {
  const queryClient = getQueryClient();
  const { data: userFullName } = useQuery(
    {
      queryKey: ["user-full-name", userId],
      queryFn: () => getUserFullNameClient(userId),
    },
    queryClient
  );
  return <T.Subtle className="text-xs">{userFullName ?? "User"}</T.Subtle>;
};
