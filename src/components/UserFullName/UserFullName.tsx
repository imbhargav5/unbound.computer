import { T } from "@/components/ui/Typography";
import { getUserFullName } from "@/data/user/user";

export const UserFullName = async ({ userId }: { userId: string }) => {
  const userFullName = await getUserFullName(userId);
  return <T.Subtle className="text-xs">{userFullName ?? "User"}</T.Subtle>;
};
