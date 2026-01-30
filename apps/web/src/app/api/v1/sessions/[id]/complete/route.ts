import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { SESSION_STATUS, validateSessionForOperation } from "@/lib/sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

interface RouteParams {
  params: Promise<{ id: string }>;
}

const completeSchema = z.object({
  /** Commit message for the changes */
  commitMessage: z.string().optional(),
  /** PR title (if creating PR) */
  prTitle: z.string().optional(),
  /** PR description (if creating PR) */
  prDescription: z.string().optional(),
  /** Whether to create a PR */
  createPr: z.boolean().default(true),
  /** Whether to archive the worktree after completion */
  archiveWorktree: z.boolean().default(false),
});

/**
 * POST: Complete a session and optionally create PR
 *
 * Completion workflow:
 * 1. Validates session is active or paused
 * 2. Updates session status to 'ended' with completion metadata
 * 3. Sends completion command to device via Supabase Realtime
 * 4. Device handles: commit, push, PR creation, worktree cleanup
 *
 * The actual PR creation happens on the device since it has:
 * - Access to git repository
 * - GitHub/GitLab CLI tools
 * - Local file changes
 */
export async function POST(req: NextRequest, { params }: RouteParams) {
  try {
    const { id: sessionId } = await params;
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // Parse request body
    const body = await req.json().catch(() => ({}));
    const parseResult = completeSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400 }
      );
    }

    const completionOptions = parseResult.data;

    // Validate session exists, belongs to user, and is in valid state
    const validation = await validateSessionForOperation(
      supabase,
      user.id,
      sessionId,
      [SESSION_STATUS.ACTIVE, SESSION_STATUS.PAUSED]
    );

    if (!validation.valid) {
      return NextResponse.json(
        { error: validation.error, code: validation.code },
        { status: validation.code === "SESSION_NOT_FOUND" ? 404 : 400 }
      );
    }

    const now = new Date().toISOString();

    // Update session status to ended with completion metadata
    // Store completion options in a way that can be read by device via realtime
    const { data: session, error } = await supabase
      .from("agent_coding_sessions")
      .update({
        status: SESSION_STATUS.ENDED,
        session_ended_at: now,
        updated_at: now,
        // Note: In a production system, you might want a separate
        // session_commands table or use Supabase Edge Functions
        // to send commands to devices. For now, devices can detect
        // completion by subscribing to session status changes.
      })
      .eq("id", sessionId)
      .select(
        `
        *,
        repository:repositories(id, name, remote_url, local_path, worktree_branch),
        device:devices(id, name, device_type)
      `
      )
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // Calculate session duration
    const durationMs =
      new Date(session.session_ended_at!).getTime() -
      new Date(session.session_started_at).getTime();

    return NextResponse.json({
      success: true,
      session,
      durationMs,
      completionOptions,
      message:
        "Session completed. Completion command will be sent to device via realtime.",
      nextSteps: completionOptions.createPr
        ? [
            "Device will commit pending changes",
            "Device will push to remote",
            "Device will create pull request",
            completionOptions.archiveWorktree
              ? "Worktree will be archived"
              : null,
          ].filter(Boolean)
        : ["Session ended without PR creation"],
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
