import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const feedbackId = searchParams.get("feedbackId");
  const locale = searchParams.get("locale");
  if (!feedbackId) {
    return NextResponse.json({ error: "Missing feedbackId" }, { status: 400 });
  }
  return NextResponse.redirect(`/${locale}/feedback/${feedbackId}`);
}
