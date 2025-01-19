import {
  getAnonFeedbackBoardBySlug,
  getAnonFeedbackThreadsByBoardSlug,
} from "@/data/anon/marketing-feedback";
import { notFound } from "next/navigation";
import { BoardDetail } from "./BoardDetail";

interface AnonBoardDetailProps {
  boardSlug: string;
}

export async function AnonBoardDetail({ boardSlug }: AnonBoardDetailProps) {
  const board = await getAnonFeedbackBoardBySlug(boardSlug);
  if (!board) return notFound();

  const feedbacks = await getAnonFeedbackThreadsByBoardSlug(boardSlug);

  return (
    <BoardDetail
      board={board}
      feedbacks={feedbacks}
      totalPages={Math.ceil(feedbacks.length / 10)}
      userType="anon"
    />
  );
}
