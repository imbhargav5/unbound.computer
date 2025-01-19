import {
  getLoggedInUserFeedbackBoardBySlug,
  getLoggedInUserFeedbackThreadsByBoardSlug,
} from "@/data/user/marketing-feedback";
import { notFound } from "next/navigation";
import { BoardDetail } from "./BoardDetail";

interface LoggedInUserBoardDetailProps {
  boardSlug: string;
}

export async function LoggedInUserBoardDetail({
  boardSlug,
}: LoggedInUserBoardDetailProps) {
  const board = await getLoggedInUserFeedbackBoardBySlug(boardSlug);
  if (!board) return notFound();

  const feedbacks = await getLoggedInUserFeedbackThreadsByBoardSlug(boardSlug);

  return (
    <BoardDetail
      board={board}
      feedbacks={feedbacks}
      totalPages={Math.ceil(feedbacks.length / 10)}
      userType="loggedIn"
    />
  );
}
