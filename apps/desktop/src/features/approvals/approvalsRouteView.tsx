import { useEffect, useMemo, useState } from "react";

import type { ApprovalRecord } from "../../lib/types";
import { DashboardBreadcrumbs, DetailRow } from "../shared/routePrimitives";

export function ApprovalsRouteView({
  approvals,
  currentApproval,
  isWorking,
  onApprove,
  onSelectApproval,
}: {
  approvals: ApprovalRecord[];
  currentApproval: ApprovalRecord | null;
  isWorking: boolean;
  onSelectApproval: (approvalId: string) => void;
  onApprove: (approvalId: string, decisionNote?: string) => void;
}) {
  const decisionQuestions = useMemo(
    () => extractApprovalDecisionQuestions(currentApproval),
    [currentApproval]
  );
  const [decisionAnswers, setDecisionAnswers] = useState<
    Record<string, string>
  >({});
  const [additionalDecisionContext, setAdditionalDecisionContext] =
    useState("");

  useEffect(() => {
    setDecisionAnswers({});
    setAdditionalDecisionContext("");
  }, [currentApproval?.id]);

  const decisionNote = useMemo(
    () =>
      composeApprovalDecisionNote(
        decisionQuestions,
        decisionAnswers,
        additionalDecisionContext
      ),
    [additionalDecisionContext, decisionAnswers, decisionQuestions]
  );
  const decisionValidationError = useMemo(
    () =>
      validateApprovalDecision(
        currentApproval,
        decisionQuestions,
        decisionAnswers,
        additionalDecisionContext
      ),
    [
      additionalDecisionContext,
      currentApproval,
      decisionAnswers,
      decisionQuestions,
    ]
  );

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs
          items={
            currentApproval
              ? [
                  { label: "Approvals" },
                  { label: currentApproval.approval_type ?? "Decision queue" },
                ]
              : [{ label: "Approvals" }]
          }
        />
        <h1>Decision queue</h1>
      </div>

      <div className="surface-grid single">
        <section className="surface-panel approvals-panel">
          <div className="surface-header">
            <h3>Approvals</h3>
          </div>
          {approvals.length ? (
            <div className="surface-list">
              {approvals.map((approval) => (
                <ApprovalQueueRow
                  approval={approval}
                  isSelected={currentApproval?.id === approval.id}
                  key={approval.id}
                  onClick={() => onSelectApproval(approval.id)}
                />
              ))}
            </div>
          ) : (
            <p className="approvals-empty-text">
              Hire approvals and issue-linked approvals will appear here.
            </p>
          )}
        </section>

        {currentApproval ? (
          <section className="surface-panel approvals-panel">
            <div className="surface-header">
              <h3>Approval Details</h3>
            </div>

            <div className="approvals-detail-stack">
              <div className="approvals-detail-header">
                <div>
                  <h2>{currentApproval.approval_type ?? "approval"}</h2>
                  <p>Status: {currentApproval.status ?? "pending"}</p>
                </div>

                {currentApproval.status === "pending" ? (
                  <button
                    className="primary-button"
                    disabled={isWorking || Boolean(decisionValidationError)}
                    onClick={() => onApprove(currentApproval.id, decisionNote)}
                    type="button"
                  >
                    Approve
                  </button>
                ) : null}
              </div>

              <div className="approvals-detail-grid">
                <DetailRow
                  label="Requested By Agent"
                  value={currentApproval.requested_by_agent_id ?? "System"}
                />
                <DetailRow
                  label="Requested By User"
                  value={currentApproval.requested_by_user_id ?? "Local Board"}
                />
                <DetailRow
                  label="Decided By"
                  value={currentApproval.decided_by_user_id ?? "Pending"}
                />
                <DetailRow
                  label="Created"
                  value={formatBoardDate(currentApproval.created_at)}
                />
                <DetailRow
                  label="Updated"
                  value={formatBoardDate(currentApproval.updated_at)}
                />
              </div>

              {decisionQuestions.length ? (
                <section className="approvals-decision-section">
                  <div className="approvals-decision-header">
                    <h3>Requested Decision</h3>
                    <p>
                      Answering this approval will resume the linked agent run
                      with your decision.
                    </p>
                  </div>
                  <div className="approvals-decision-stack">
                    {decisionQuestions.map((question, index) => {
                      const answerKey = approvalDecisionAnswerKey(
                        question,
                        index
                      );
                      const selectedAnswer = decisionAnswers[answerKey] ?? "";
                      return (
                        <div
                          className="approvals-decision-card"
                          key={answerKey}
                        >
                          <div className="approvals-decision-card-copy">
                            {question.header ? (
                              <span className="approvals-decision-chip">
                                {question.header}
                              </span>
                            ) : null}
                            <strong>{question.question}</strong>
                          </div>
                          {question.options.length ? (
                            <div className="approvals-decision-options">
                              {question.options.map((option) => {
                                const isSelected =
                                  selectedAnswer === option.label;
                                return (
                                  <button
                                    className={
                                      isSelected
                                        ? "approvals-decision-option active"
                                        : "approvals-decision-option"
                                    }
                                    key={option.label}
                                    onClick={() =>
                                      setDecisionAnswers((previous) => ({
                                        ...previous,
                                        [answerKey]: option.label,
                                      }))
                                    }
                                    type="button"
                                  >
                                    <span>{option.label}</span>
                                    {option.description ? (
                                      <small>{option.description}</small>
                                    ) : null}
                                  </button>
                                );
                              })}
                            </div>
                          ) : (
                            <textarea
                              className="approvals-decision-textarea"
                              onChange={(event) =>
                                setDecisionAnswers((previous) => ({
                                  ...previous,
                                  [answerKey]: event.target.value,
                                }))
                              }
                              placeholder="Add the board's answer..."
                              rows={3}
                              value={selectedAnswer}
                            />
                          )}
                        </div>
                      );
                    })}
                  </div>

                  {currentApproval.status === "pending" ? (
                    <label className="approvals-decision-note-field">
                      <span>Additional Context</span>
                      <textarea
                        className="approvals-decision-textarea"
                        onChange={(event) =>
                          setAdditionalDecisionContext(event.target.value)
                        }
                        placeholder="Optional details for the agent..."
                        rows={3}
                        value={additionalDecisionContext}
                      />
                    </label>
                  ) : null}

                  {decisionValidationError ? (
                    <p className="approvals-decision-error">
                      {decisionValidationError}
                    </p>
                  ) : null}
                </section>
              ) : null}

              {currentApproval.decision_note ? (
                <section className="approvals-answer-section">
                  <h3>Decision Note</h3>
                  <pre>{currentApproval.decision_note}</pre>
                </section>
              ) : null}

              {currentApproval.payload &&
              Object.keys(currentApproval.payload).length > 0 ? (
                <section className="approvals-payload-section">
                  <h3>Payload</h3>
                  <pre>{formatApprovalPayload(currentApproval.payload)}</pre>
                </section>
              ) : null}
            </div>
          </section>
        ) : (
          <section className="surface-panel approvals-panel">
            <div className="surface-header">
              <h3>Approval Details</h3>
            </div>
            <div className="workspace-empty-state approvals-empty-state">
              <h3>Select an approval</h3>
              <p>Approval payloads and decisions show here.</p>
            </div>
          </section>
        )}
      </div>
    </section>
  );
}

type ApprovalDecisionOption = {
  label: string;
  description: string | null;
};

type ApprovalDecisionQuestion = {
  id: string | null;
  header: string | null;
  question: string;
  options: ApprovalDecisionOption[];
};

function ApprovalQueueRow({
  approval,
  isSelected,
  onClick,
}: {
  approval: ApprovalRecord;
  isSelected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={
        isSelected ? "approval-queue-row active" : "approval-queue-row"
      }
      onClick={onClick}
      type="button"
    >
      <div className="approval-queue-row-main">
        <strong>{approval.approval_type ?? "approval"}</strong>
        <span>{formatBoardDate(approval.created_at)}</span>
      </div>
      <span className="approval-queue-row-trailing">
        {approval.status ?? "pending"}
      </span>
    </button>
  );
}

function extractApprovalDecisionQuestions(
  approval: ApprovalRecord | null
): ApprovalDecisionQuestion[] {
  const payload = approval?.payload;
  if (!payload || typeof payload !== "object") {
    return [];
  }

  const rawQuestions = Array.isArray(payload.questions)
    ? payload.questions
    : typeof payload.question === "string" && payload.question.trim()
      ? [
          {
            question: payload.question,
            options: Array.isArray(payload.options) ? payload.options : [],
          },
        ]
      : [];

  return rawQuestions
    .map((value) => parseApprovalDecisionQuestion(value))
    .filter((value): value is ApprovalDecisionQuestion => value !== null);
}

function parseApprovalDecisionQuestion(
  value: unknown
): ApprovalDecisionQuestion | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const record = value as Record<string, unknown>;

  const questionValue =
    typeof record.question === "string"
      ? record.question.trim()
      : typeof record.prompt === "string"
        ? record.prompt.trim()
        : "";
  if (!questionValue) {
    return null;
  }

  const idValue =
    typeof record.id === "string" && record.id.trim() ? record.id.trim() : null;
  const headerValue =
    typeof record.header === "string" && record.header.trim()
      ? record.header.trim()
      : typeof record.label === "string" && record.label.trim()
        ? record.label.trim()
        : null;

  return {
    id: idValue,
    header: headerValue,
    question: questionValue,
    options: parseApprovalDecisionOptions(record.options),
  };
}

function parseApprovalDecisionOptions(
  value: unknown
): ApprovalDecisionOption[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((entry) => {
      if (typeof entry === "string") {
        const label = entry.trim();
        return label ? { label, description: null } : null;
      }
      if (!entry || typeof entry !== "object") {
        return null;
      }
      const record = entry as Record<string, unknown>;

      const label =
        typeof record.label === "string" && record.label.trim()
          ? record.label.trim()
          : typeof record.title === "string" && record.title.trim()
            ? record.title.trim()
            : null;
      if (!label) {
        return null;
      }

      const description =
        typeof record.description === "string" && record.description.trim()
          ? record.description.trim()
          : null;
      return { label, description };
    })
    .filter((entry): entry is ApprovalDecisionOption => entry !== null);
}

function approvalDecisionAnswerKey(
  question: ApprovalDecisionQuestion,
  index: number
) {
  return question.id ?? `question-${index}`;
}

function composeApprovalDecisionNote(
  questions: ApprovalDecisionQuestion[],
  answers: Record<string, string>,
  additionalContext: string
) {
  const sections = questions
    .map((question, index) => {
      const answer =
        answers[approvalDecisionAnswerKey(question, index)]?.trim();
      if (!answer) {
        return null;
      }
      const label = question.header ?? question.question;
      return `${label}: ${answer}`;
    })
    .filter((value): value is string => Boolean(value));

  const trimmedContext = additionalContext.trim();
  if (trimmedContext) {
    sections.push(`Additional context:\n${trimmedContext}`);
  }

  return sections.join("\n\n").trim();
}

function validateApprovalDecision(
  approval: ApprovalRecord | null,
  questions: ApprovalDecisionQuestion[],
  answers: Record<string, string>,
  additionalContext: string
) {
  if (
    approval?.status !== "pending" ||
    approval.approval_type !== "agent_decision"
  ) {
    return null;
  }

  if (!questions.length) {
    return additionalContext.trim()
      ? null
      : "Add the board's decision before approving.";
  }

  for (let index = 0; index < questions.length; index += 1) {
    const question = questions[index];
    const answer = answers[approvalDecisionAnswerKey(question, index)]?.trim();
    if (!answer) {
      return question.options.length
        ? `Choose an option for "${question.question}".`
        : `Add an answer for "${question.question}".`;
    }
  }

  return null;
}

function formatApprovalPayload(payload: Record<string, unknown>) {
  return Object.entries(payload)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}: ${formatApprovalPayloadValue(value)}`)
    .join("\n");
}

function formatApprovalPayloadValue(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }

  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    value === null ||
    value === undefined
  ) {
    return String(value);
  }

  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function formatBoardDate(value: string | null | undefined) {
  if (!value) {
    return "Unknown";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}
