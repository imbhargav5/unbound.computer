import { Suspense } from "react";
import { serverGetClaimType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";
import { filtersSchema } from "../../[feedbackId]/schema";
import { AdminBoardDetail } from "./admin-board-detail";
import { AnonBoardDetail } from "./anon-board-detail";
import { BoardDetailFallback } from "./board-detail-fallback";
import { LoggedInUserBoardDetail } from "./logged-in-user-board-detail";

async function BoardDetailPageContent(props: {
  params: Promise<{ boardSlug: string;  }>;
  searchParams: Promise<unknown>;
}) {
  const params = await props.params;
  const searchParams = await props.searchParams;
  const validatedSearchParams = filtersSchema.parse(searchParams);
  const userRoleType = await serverGetClaimType();
  const { boardSlug } = params;
  const suspenseKey = JSON.stringify(validatedSearchParams);

  return (
    <div className="py-6">
      <Suspense fallback={<BoardDetailFallback />} key={suspenseKey}>
        {userRoleType === userRoles.ANON && (
          <AnonBoardDetail
            boardSlug={boardSlug}
            filters={validatedSearchParams}
          />
        )}
        {userRoleType === userRoles.USER && (
          <LoggedInUserBoardDetail
            boardSlug={boardSlug}
            filters={validatedSearchParams}
          />
        )}
        {userRoleType === userRoles.ADMIN && (
          <AdminBoardDetail
            boardSlug={boardSlug}
            filters={validatedSearchParams}
          />
        )}
      </Suspense>
    </div>
  );
}

async function BoardDetailPage(props: {
  params: Promise<{ boardSlug: string; }>;
  searchParams: Promise<unknown>;
}) {
  return (
    <Suspense>
      <BoardDetailPageContent
        params={props.params}
        searchParams={props.searchParams}
      />
    </Suspense>
  );
}

export default BoardDetailPage;
