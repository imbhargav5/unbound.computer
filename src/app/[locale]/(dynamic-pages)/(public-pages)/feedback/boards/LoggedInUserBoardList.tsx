import { getLoggedInUserFeedbackBoards } from "@/data/user/marketing-feedback";
import { BoardList } from "./BoardList";

export async function LoggedInUserBoardList() {
  const boards = await getLoggedInUserFeedbackBoards();
  return <BoardList boards={boards} userType="loggedIn" />;
}
