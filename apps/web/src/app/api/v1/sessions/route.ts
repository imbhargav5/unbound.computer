import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  SESSION_STATUS,
  validateDeviceOwnership,
  validateRepositoryOwnership,
  validateSessionLimits,
} from "@/lib/sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

const sessionCreateSchema = z.object({
  deviceId: z.string().uuid(),
  repositoryId: z.string().uuid(),
  currentBranch: z.string().optional(),
  workingDirectory: z.string().optional(),
});

/**
 * POST: Create a new coding session
 *
 * Creates a session and validates:
 * - User owns the device
 * - User owns the repository
 * - Session limits are not exceeded
 */
export async function POST(req: NextRequest) {
  try {
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await req.json();
    const parseResult = sessionCreateSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400 }
      );
    }

    const { deviceId, repositoryId, currentBranch, workingDirectory } =
      parseResult.data;

    // Validate device ownership
    const deviceCheck = await validateDeviceOwnership(
      supabase,
      user.id,
      deviceId
    );
    if (!deviceCheck.valid) {
      return NextResponse.json(
        { error: deviceCheck.error, code: deviceCheck.code },
        { status: 403 }
      );
    }

    // Validate repository ownership
    const repoCheck = await validateRepositoryOwnership(
      supabase,
      user.id,
      repositoryId
    );
    if (!repoCheck.valid) {
      return NextResponse.json(
        { error: repoCheck.error, code: repoCheck.code },
        { status: 403 }
      );
    }

    // Validate session limits
    const limitsCheck = await validateSessionLimits(
      supabase,
      user.id,
      deviceId
    );
    if (!limitsCheck.valid) {
      return NextResponse.json(
        { error: limitsCheck.error, code: limitsCheck.code },
        { status: 429 }
      );
    }

    // Create the session
    const { data: session, error } = await supabase
      .from("coding_sessions")
      .insert({
        user_id: user.id,
        device_id: deviceId,
        repository_id: repositoryId,
        current_branch: currentBranch ?? null,
        working_directory: workingDirectory ?? null,
        status: SESSION_STATUS.ACTIVE,
        session_started_at: new Date().toISOString(),
        last_heartbeat_at: new Date().toISOString(),
      })
      .select(
        `
        *,
        repository:repositories(id, name, remote_url, local_path),
        device:devices(id, name, device_type)
      `
      )
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json(session, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}

/**
 * GET: List user's sessions
 *
 * Query parameters:
 * - status: Filter by status (active, paused, ended)
 * - deviceId: Filter by device
 * - repositoryId: Filter by repository
 * - limit: Number of results (default 50, max 100)
 */
export async function GET(req: NextRequest) {
  try {
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { searchParams } = new URL(req.url);
    const statusParam = searchParams.get("status");
    const deviceId = searchParams.get("deviceId");
    const repositoryId = searchParams.get("repositoryId");

    // Validate status is a valid enum value
    const validStatuses = Object.values(SESSION_STATUS);
    const status =
      statusParam &&
      validStatuses.includes(statusParam as (typeof validStatuses)[number])
        ? (statusParam as (typeof validStatuses)[number])
        : null;
    const limit = Math.min(
      Number.parseInt(searchParams.get("limit") ?? "50", 10),
      100
    );

    let query = supabase
      .from("coding_sessions")
      .select(
        `
        *,
        repository:repositories(id, name, remote_url, local_path),
        device:devices(id, name, device_type)
      `
      )
      .eq("user_id", user.id)
      .order("session_started_at", { ascending: false })
      .limit(limit);

    if (status) {
      query = query.eq("status", status);
    }

    if (deviceId) {
      query = query.eq("device_id", deviceId);
    }

    if (repositoryId) {
      query = query.eq("repository_id", repositoryId);
    }

    const { data, error } = await query;

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
