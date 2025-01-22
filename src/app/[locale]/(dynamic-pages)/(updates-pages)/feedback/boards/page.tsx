import { PageHeading } from "@/components/PageHeading";
import { Button } from "@/components/ui/button";
import { serverGetUserType } from "@/utils/server/serverGetUserType";
import { userRoles } from "@/utils/userTypes";
import { Fragment, Suspense } from "react";
import { CreateBoardDialog } from "../CreateBoardDialog";
import { AdminBoardList } from "./AdminBoardList";
import { AnonBoardList } from "./AnonBoardList";
import { LoggedInUserBoardList } from "./LoggedInUserBoardList";

async function FeedbackBoardsPage() {
  const userRoleType = await serverGetUserType();

  return (
    <Fragment>
      <div className="flex justify-between items-center">
        <PageHeading
          title="Feedback Boards"
          subTitle="Browse and participate in topic-specific feedback discussions."
        />

        {userRoleType === userRoles.ADMIN && (
          <CreateBoardDialog className="w-fit">
            <Button variant="default">Create Board</Button>
          </CreateBoardDialog>
        )}
      </div>

      <div className="w-full h-full max-h-[88vh]">
        <Suspense fallback={<div>Loading...</div>}>
          {userRoleType === userRoles.ANON && <AnonBoardList />}
          {userRoleType === userRoles.USER && <LoggedInUserBoardList />}
          {userRoleType === userRoles.ADMIN && <AdminBoardList />}
        </Suspense>
      </div>
    </Fragment>
  );
}

export default FeedbackBoardsPage;
