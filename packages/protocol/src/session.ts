import { z } from "zod";

/**
 * Start a new Claude Code session
 */
export const StartSessionSchema = z.object({
  command: z.literal("START_SESSION"),
  repositoryId: z.string().uuid(),
  branch: z.string().optional(),
  workingDirectory: z.string().optional(),
});

/**
 * End the current session
 */
export const EndSessionSchema = z.object({
  command: z.literal("END_SESSION"),
});

/**
 * Pause the current session
 */
export const PauseSessionSchema = z.object({
  command: z.literal("PAUSE_SESSION"),
});

/**
 * Resume a paused session
 */
export const ResumeSessionSchema = z.object({
  command: z.literal("RESUME_SESSION"),
});

/**
 * User input to Claude Code
 */
export const InputSchema = z.object({
  command: z.literal("INPUT"),
  content: z.string(),
  inputType: z.enum(["prompt", "confirmation", "rejection"]),
});

/**
 * Output from Claude Code
 */
export const OutputSchema = z.object({
  command: z.literal("OUTPUT"),
  content: z.string(),
  outputType: z.enum(["text", "tool_use", "tool_result", "error", "status"]),
  isComplete: z.boolean().optional(),
});

/**
 * Union of all session commands
 */
export const SessionCommandSchema = z.discriminatedUnion("command", [
  StartSessionSchema,
  EndSessionSchema,
  PauseSessionSchema,
  ResumeSessionSchema,
  InputSchema,
  OutputSchema,
]);

export type StartSession = z.infer<typeof StartSessionSchema>;
export type EndSession = z.infer<typeof EndSessionSchema>;
export type PauseSession = z.infer<typeof PauseSessionSchema>;
export type ResumeSession = z.infer<typeof ResumeSessionSchema>;
export type Input = z.infer<typeof InputSchema>;
export type Output = z.infer<typeof OutputSchema>;
export type SessionCommand = z.infer<typeof SessionCommandSchema>;

/**
 * Validate a session command
 */
export function validateSessionCommand(data: unknown): SessionCommand {
  return SessionCommandSchema.parse(data);
}

/**
 * Safe parse a session command
 */
export function parseSessionCommand(
  data: unknown
):
  | { success: true; data: SessionCommand }
  | { success: false; error: z.ZodError } {
  const result = SessionCommandSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error };
}
