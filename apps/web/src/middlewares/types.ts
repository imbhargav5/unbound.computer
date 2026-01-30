import type { NextRequest, NextResponse } from "next/server";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";

export type MiddlewareUser = UserClaimsSchemaType | null;

export type MiddlewareFunction = (
  request: NextRequest,
  maybeUser: MiddlewareUser
) => Promise<[NextResponse, MiddlewareUser]>;

export interface MiddlewareConfig {
  matcher: string | string[];
  middleware: MiddlewareFunction;
}
