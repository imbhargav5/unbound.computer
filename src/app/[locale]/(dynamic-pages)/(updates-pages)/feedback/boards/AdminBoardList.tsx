import { getFeedbackBoards } from "@/data/admin/marketing-feedback";
import { BoardList } from "./BoardList";

export async function AdminBoardList() {
  const boards = await getFeedbackBoards();
  return <BoardList boards={boards} userType="admin" />;
}
