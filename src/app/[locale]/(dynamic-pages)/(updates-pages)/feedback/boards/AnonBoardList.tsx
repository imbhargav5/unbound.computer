import { getAnonFeedbackBoards } from "@/data/anon/marketing-feedback";
import { BoardList } from "./BoardList";

export async function AnonBoardList() {
  const boards = await getAnonFeedbackBoards();
  return <BoardList boards={boards} userType="anon" />;
}
