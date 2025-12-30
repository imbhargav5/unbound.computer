import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseUnkeyClient } from "@/supabase-clients/unkey/create-supabase-unkey-client";

const sessionCreateSchema = z.object({
  deviceId: z.string().uuid(),
  repositoryId: z.string().uuid(),
  sessionPid: z.number().optional(),
  currentBranch: z.string().optional(),
  workingDirectory: z.string().optional(),
});

const sessionUpdateSchema = z.object({
  status: z.enum(["active", "paused", "ended"]).optional(),
  currentBranch: z.string().optional(),
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

/**
 * OPTIONS handler for CORS preflight
 */
export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

/**
 * POST: Create a new coding session
 */
export async function POST(req: NextRequest) {
  try {
    const supabaseClient = await createSupabaseUnkeyClient(req);
    const {
      data: { user },
    } = await supabaseClient.auth.getUser();

    if (!user) {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401, headers: corsHeaders }
      );
    }

    const body = await req.json();
    const parseResult = sessionCreateSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const validated = parseResult.data;

    const { data, error } = await supabaseClient
      .from("coding_sessions")
      .insert({
        user_id: user.id,
        device_id: validated.deviceId,
        repository_id: validated.repositoryId,
        session_pid: validated.sessionPid ?? null,
        current_branch: validated.currentBranch ?? null,
        working_directory: validated.workingDirectory ?? null,
        status: "active",
      })
      .select()
      .single();

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500, headers: corsHeaders }
      );
    }

    return NextResponse.json(data, { headers: corsHeaders });
  } catch (error) {
    return NextResponse.json(
      { error: String(error) },
      { status: 500, headers: corsHeaders }
    );
  }
}

/**
 * PATCH: Update session (heartbeat, status change, end session)
 */
export async function PATCH(req: NextRequest) {
  try {
    const supabaseClient = await createSupabaseUnkeyClient(req);
    const {
      data: { user },
    } = await supabaseClient.auth.getUser();

    if (!user) {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401, headers: corsHeaders }
      );
    }

    const { searchParams } = new URL(req.url);
    const sessionId = searchParams.get("sessionId");

    if (!sessionId) {
      return NextResponse.json(
        { error: "sessionId query parameter is required" },
        { status: 400, headers: corsHeaders }
      );
    }

    const body = await req.json();
    const parseResult = sessionUpdateSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const validated = parseResult.data;

    const updateData: Record<string, unknown> = {
      last_heartbeat_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    if (validated.status) {
      updateData.status = validated.status;
      if (validated.status === "ended") {
        updateData.session_ended_at = new Date().toISOString();
      }
    }

    if (validated.currentBranch) {
      updateData.current_branch = validated.currentBranch;
    }

    const { data, error } = await supabaseClient
      .from("coding_sessions")
      .update(updateData)
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .select()
      .single();

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500, headers: corsHeaders }
      );
    }

    return NextResponse.json(data, { headers: corsHeaders });
  } catch (error) {
    return NextResponse.json(
      { error: String(error) },
      { status: 500, headers: corsHeaders }
    );
  }
}

/**
 * GET: List active sessions (optionally filtered by device or repository)
 */
export async function GET(req: NextRequest) {
  try {
    const supabaseClient = await createSupabaseUnkeyClient(req);
    const {
      data: { user },
    } = await supabaseClient.auth.getUser();

    if (!user) {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401, headers: corsHeaders }
      );
    }

    const { searchParams } = new URL(req.url);
    const deviceId = searchParams.get("deviceId");
    const repositoryId = searchParams.get("repositoryId");
    const status = searchParams.get("status");

    let query = supabaseClient
      .from("coding_sessions")
      .select(
        `
        *,
        repository:repositories(id, name, local_path, remote_url),
        device:devices(id, name, device_type)
      `
      )
      .eq("user_id", user.id)
      .order("session_started_at", { ascending: false });

    if (deviceId) {
      query = query.eq("device_id", deviceId);
    }

    if (repositoryId) {
      query = query.eq("repository_id", repositoryId);
    }

    if (status) {
      query = query.eq("status", status);
    }

    const { data, error } = await query;

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500, headers: corsHeaders }
      );
    }

    return NextResponse.json(data, { headers: corsHeaders });
  } catch (error) {
    return NextResponse.json(
      { error: String(error) },
      { status: 500, headers: corsHeaders }
    );
  }
}
