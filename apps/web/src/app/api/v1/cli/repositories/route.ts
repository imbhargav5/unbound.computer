import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseUnkeyClient } from "@/supabase-clients/unkey/create-supabase-unkey-client";

const repositorySyncSchema = z.object({
  deviceId: z.string().uuid(),
  name: z.string().min(1),
  localPath: z.string().min(1),
  remoteUrl: z.string().optional(),
  defaultBranch: z.string().optional(),
  isWorktree: z.boolean().default(false),
  parentRepositoryId: z.string().uuid().optional(),
  worktreeBranch: z.string().optional(),
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

/**
 * OPTIONS handler for CORS preflight
 */
export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

/**
 * POST: Upsert a repository (on conflict: device_id + local_path)
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
    const parseResult = repositorySyncSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const validated = parseResult.data;

    // Upsert repository
    const { data, error } = await supabaseClient
      .from("repositories")
      .upsert(
        {
          user_id: user.id,
          device_id: validated.deviceId,
          name: validated.name,
          local_path: validated.localPath,
          remote_url: validated.remoteUrl ?? null,
          default_branch: validated.defaultBranch ?? null,
          is_worktree: validated.isWorktree,
          parent_repository_id: validated.parentRepositoryId ?? null,
          worktree_branch: validated.worktreeBranch ?? null,
          last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
        {
          onConflict: "device_id,local_path",
        }
      )
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
 * GET: List repositories with worktrees and active sessions nested
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

    let query = supabaseClient
      .from("repositories")
      .select(
        `
        *,
        device:devices(id, name, device_type),
        worktrees:repositories!parent_repository_id(
          id, name, local_path, worktree_branch, status
        ),
        active_sessions:agent_coding_sessions!repository_id(
          id, status, session_started_at, current_branch
        )
      `
      )
      .eq("user_id", user.id)
      .eq("is_worktree", false)
      .eq("status", "active")
      .order("updated_at", { ascending: false });

    if (deviceId) {
      query = query.eq("device_id", deviceId);
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
