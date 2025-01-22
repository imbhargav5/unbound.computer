import { serverGetUserType } from "@/utils/server/serverGetUserType";
import { userRoles } from "@/utils/userTypes";
import { Suspense } from "react";
import { AdminBoardDetail } from "./AdminBoardDetail";
import { AnonBoardDetail } from "./AnonBoardDetail";
import { BoardDetailFallback } from "./BoardDetailFallback";
import { LoggedInUserBoardDetail } from "./LoggedInUserBoardDetail";

async function BoardDetailPage(props: {
  params: Promise<{ boardSlug: string }>;
}) {
  const params = await props.params;
  const userRoleType = await serverGetUserType();
  const { boardSlug } = params;

  return (
    <Suspense fallback={<BoardDetailFallback />}>
      {userRoleType === userRoles.ANON && (
        <AnonBoardDetail boardSlug={boardSlug} />
      )}
      {userRoleType === userRoles.USER && (
        <LoggedInUserBoardDetail boardSlug={boardSlug} />
      )}
      {userRoleType === userRoles.ADMIN && (
        <AdminBoardDetail boardSlug={boardSlug} />
      )}
    </Suspense>
  );
}

export default BoardDetailPage;
