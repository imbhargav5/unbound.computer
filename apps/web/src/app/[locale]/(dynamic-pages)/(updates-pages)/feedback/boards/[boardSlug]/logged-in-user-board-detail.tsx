import { notFound } from "next/navigation";
import {
  getLoggedInUserFeedbackBoardBySlug,
  getPaginatedLoggedInUserFeedbackThreadsByBoardId,
} from "@/data/user/marketing-feedback";
import type { FiltersSchema } from "../../[feedbackId]/schema";
import { BoardDetail } from "./board-detail";

interface LoggedInUserBoardDetailProps {
  boardSlug: string;
  filters: FiltersSchema;
}

export async function LoggedInUserBoardDetail({
  boardSlug,
  filters,
}: LoggedInUserBoardDetailProps) {
  const board = await getLoggedInUserFeedbackBoardBySlug(boardSlug);
  if (!board) return notFound();

  const { data: feedbacks, count: totalPages } =
    await getPaginatedLoggedInUserFeedbackThreadsByBoardId({
      boardId: board.id,
      ...filters,
    });

  return (
    <BoardDetail
      board={board}
      feedbacks={feedbacks}
      totalPages={totalPages ?? 0}
      userType="loggedIn"
    />
  );
}
