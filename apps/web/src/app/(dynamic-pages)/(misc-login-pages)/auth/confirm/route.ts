import { type NextRequest, NextResponse } from "next/server";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  console.log("searchParams", searchParams.toString());
  const token_hash = searchParams.get("token_hash");
  const type = searchParams.get("type");
  // For recovery (password reset), redirect to update-password page
  const defaultNext = type === "recovery" ? "/update-password" : "/dashboard";
  const next = searchParams.get("next") ?? defaultNext;
  if (token_hash) {
    const supabase = await createSupabaseUserRouteHandlerClient();
    // Use the appropriate type for verifyOtp based on the request type
    const { error } = await supabase.auth.verifyOtp({
      type: type === "recovery" ? "recovery" : "email",
      token_hash,
    });
    if (!error) {
      return NextResponse.redirect(new URL(`/${next.slice(1)}`, req.url));
    }
    console.log("error", error);
  }
  // return the user to an error page with some instructions
  return NextResponse.redirect(new URL("/auth/auth-code-error", req.url));
}
