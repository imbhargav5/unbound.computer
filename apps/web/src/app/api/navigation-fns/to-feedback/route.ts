import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const feedbackId = searchParams.get("feedbackId");
  if (!feedbackId) {
    return NextResponse.json({ error: "Missing feedbackId" }, { status: 400 });
  }
  return NextResponse.redirect(`/feedback/${feedbackId}`);
}
