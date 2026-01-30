import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";
import { toSiteURL } from "@/utils/helpers";
import { userClaimsSchema } from "@/utils/zod-schemas/user-claims-schema";

const paramsSchema = z.object({
  invitationId: z.coerce.string(),
});

export async function GET(
  _req: NextRequest,
  props: {
    params: Promise<{ invitationId: string }>;
  }
) {
  const params = await props.params;
  const { success } = paramsSchema.safeParse(params);
  if (!success) {
    return NextResponse.json({
      error: "Invalid invitation ID",
    });
  }
  const { invitationId } = paramsSchema.parse(params);

  const supabaseClient = await createSupabaseUserRouteHandlerClient();
  const { data, error } = await supabaseClient.auth.getClaims();
  if (error) {
    throw error;
  }
  const userClaims = userClaimsSchema.parse(data?.claims);

  if (!userClaims) {
    const url = new URL(toSiteURL("/login"));
    url.searchParams.append(
      "next",
      `/user/invitations/${encodeURIComponent(invitationId)}`
    );
    url.searchParams.append("nextActionType", "invitationPending");
    return NextResponse.redirect(url.toString());
  }

  if (typeof invitationId === "string") {
    return NextResponse.redirect(
      toSiteURL(`/user/invitations/${invitationId}`)
    );
  }
  return NextResponse.json({
    error: "Invalid invitation ID",
  });
}
