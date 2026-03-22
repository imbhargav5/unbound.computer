import type { SessionMessage } from "./types";

export function shouldHideSyntheticSessionMessage(message: SessionMessage) {
  return shouldHideSyntheticSessionContent(message.content);
}

export function shouldHideSyntheticSessionContent(content: unknown) {
  if (typeof content !== "string") {
    return false;
  }

  const trimmed = content.trim();
  if (!trimmed) {
    return false;
  }

  return (
    isSyntheticIssueSeedMessage(trimmed) || isSyntheticAgentRunPrompt(trimmed)
  );
}

function isSyntheticIssueSeedMessage(text: string) {
  const lines = text.split(/\r?\n/);
  return (
    lines.length === 5 &&
    lines[0]?.startsWith("Conversation: ") === true &&
    lines[1]?.startsWith("Title: ") === true &&
    lines[2]?.startsWith("Description: ") === true &&
    lines[3]?.startsWith("Status: ") === true &&
    lines[4]?.startsWith("Priority: ") === true
  );
}

function isSyntheticAgentRunPrompt(text: string) {
  const hasDaemonPromptSections =
    text.includes("Governance rules:") &&
    text.includes("Board helper commands:");
  if (!hasDaemonPromptSections) {
    return false;
  }

  return (
    text.includes("This run is focused on issue ") ||
    text.includes("Inspect work assigned to ") ||
    text.includes("You are ") ||
    text.includes("\nIssue: ")
  );
}
