import {
    getFeedbackBoardBySlug,
    getFeedbackThreadsByBoardSlug,
} from "@/data/admin/marketing-feedback";
import { notFound } from "next/navigation";
import { BoardDetail } from "./BoardDetail";

interface AdminBoardDetailProps {
    boardSlug: string;
}

export async function AdminBoardDetail({ boardSlug }: AdminBoardDetailProps) {
    const board = await getFeedbackBoardBySlug(boardSlug);
    if (!board) return notFound();

    const feedbacks = await getFeedbackThreadsByBoardSlug(boardSlug);

    return (
        <BoardDetail
            board={board}
            feedbacks={feedbacks}
            totalPages={Math.ceil(feedbacks.length / 10)}
            userType="admin"
        />
    );
}
