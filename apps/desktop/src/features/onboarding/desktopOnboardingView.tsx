import {
  LaptopMinimal,
  MessagesSquare,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import { useMemo, useState } from "react";

interface DesktopOnboardingViewProps {
  deviceName?: string | null;
  errorMessage?: string | null;
  isCompleting?: boolean;
  onComplete: () => void | Promise<void>;
  repositoryCount?: number;
}

interface OnboardingPage {
  description: string;
  eyebrow: string;
  features: string[];
  title: string;
  visual: "welcome" | "devices" | "sessions";
}

export function DesktopOnboardingView({
  deviceName,
  errorMessage,
  isCompleting = false,
  onComplete,
  repositoryCount = 0,
}: DesktopOnboardingViewProps) {
  const [currentPage, setCurrentPage] = useState(0);

  const pages = useMemo<OnboardingPage[]>(
    () => [
      {
        eyebrow: "Welcome",
        title: "Welcome to Unbound Desktop",
        description:
          "Keep your coding workspace, session history, and runtime controls in one place the first time you open the app.",
        features: [
          "Start from a focused desktop shell built for active sessions.",
          "Keep daemon, repositories, and runtime status visible without leaving the app.",
        ],
        visual: "welcome",
      },
      {
        eyebrow: "Multi-device",
        title: "Your machines stay in sync",
        description: `${deviceName ?? "This device"} becomes part of the same workspace graph as your other development machines, so switching context does not mean losing track.`,
        features: [
          "Track which machine is available before you jump into a conversation.",
          "Keep repository routing and device identity attached to the current workspace.",
        ],
        visual: "devices",
      },
      {
        eyebrow: "Sessions",
        title: "Every conversation stays attached to the work",
        description:
          repositoryCount > 0
            ? `You already have ${repositoryCount} ${repositoryCount === 1 ? "repository" : "repositories"} connected. Unbound keeps the active conversation, files, and runtime state together.`
            : "Add repositories, open conversations, and keep the file tree, terminal, and session timeline attached to the same workspace.",
        features: [
          "Follow model output, file changes, and runtime state from one screen.",
          "Move from dashboard to conversation detail without reloading context.",
        ],
        visual: "sessions",
      },
    ],
    [deviceName, repositoryCount],
  );
  const isLastPage = currentPage === pages.length - 1;
  const activePage = pages[currentPage];

  const handleAdvance = () => {
    if (isLastPage) {
      void onComplete();
      return;
    }

    setCurrentPage((page) => Math.min(page + 1, pages.length - 1));
  };

  const handleBack = () => {
    if (currentPage === 0) {
      void onComplete();
      return;
    }

    setCurrentPage((page) => Math.max(page - 1, 0));
  };

  return (
    <div className="desktop-onboarding-shell">
      <div className="desktop-onboarding-card">
        <div className="desktop-onboarding-grid">
          <section className="desktop-onboarding-copy">
            <span className="desktop-onboarding-eyebrow">
              {activePage.eyebrow}
            </span>
            <h1>{activePage.title}</h1>
            <p className="desktop-onboarding-description">
              {activePage.description}
            </p>
            <ul className="desktop-onboarding-feature-list">
              {activePage.features.map((feature) => (
                <li key={feature}>
                  <ShieldCheck aria-hidden="true" size={16} />
                  <span>{feature}</span>
                </li>
              ))}
            </ul>
          </section>

          <section
            aria-label={`${activePage.eyebrow} preview`}
            className="desktop-onboarding-visual"
          >
            {activePage.visual === "welcome" ? <WelcomePreview /> : null}
            {activePage.visual === "devices" ? (
              <DevicesPreview deviceName={deviceName} />
            ) : null}
            {activePage.visual === "sessions" ? <SessionsPreview /> : null}
          </section>
        </div>

        <div className="desktop-onboarding-footer">
          <div
            aria-label="Onboarding progress"
            className="desktop-onboarding-pagination"
          >
            {pages.map((page, index) => (
              <button
                aria-label={`Go to ${page.eyebrow}`}
                className={
                  index === currentPage
                    ? "desktop-onboarding-dot is-active"
                    : "desktop-onboarding-dot"
                }
                key={page.eyebrow}
                onClick={() => setCurrentPage(index)}
                type="button"
              />
            ))}
          </div>

          <div className="desktop-onboarding-actions">
            <button
              className="secondary-button"
              disabled={isCompleting}
              onClick={handleBack}
              type="button"
            >
              {currentPage === 0 ? "Skip" : "Back"}
            </button>
            <button
              className="primary-button"
              disabled={isCompleting}
              onClick={handleAdvance}
              type="button"
            >
              {isCompleting ? "Saving..." : isLastPage ? "Get started" : "Next"}
            </button>
          </div>
        </div>

        {errorMessage ? (
          <p className="desktop-onboarding-error" role="alert">
            {errorMessage}
          </p>
        ) : null}
      </div>
    </div>
  );
}

function WelcomePreview() {
  return (
    <div className="desktop-onboarding-preview-stack">
      <div className="desktop-onboarding-hero">
        <div className="desktop-onboarding-hero-badge">
          <Sparkles aria-hidden="true" size={18} />
          Desktop shell
        </div>
        <div className="desktop-onboarding-hero-mark">
          <LaptopMinimal aria-hidden="true" size={42} />
        </div>
        <strong>Unbound keeps your local runtime close to the work.</strong>
        <p>
          Move from dashboard to files, terminal, and session detail without
          dropping context.
        </p>
      </div>

      <div className="desktop-onboarding-mini-grid">
        <div className="desktop-onboarding-mini-card">
          <span>Repositories</span>
          <strong>Local workspace routing</strong>
        </div>
        <div className="desktop-onboarding-mini-card">
          <span>Runtime</span>
          <strong>Daemon compatibility at startup</strong>
        </div>
      </div>
    </div>
  );
}

function DevicesPreview({ deviceName }: { deviceName?: string | null }) {
  return (
    <div className="desktop-onboarding-device-list">
      <PreviewDeviceCard
        isActive
        name={deviceName ?? "Current desktop"}
        status="Online now"
      />
      <PreviewDeviceCard name="Remote workstation" status="Ready for handoff" />
      <PreviewDeviceCard name="Travel laptop" status="Last seen yesterday" />
    </div>
  );
}

function PreviewDeviceCard({
  isActive = false,
  name,
  status,
}: {
  isActive?: boolean;
  name: string;
  status: string;
}) {
  return (
    <div
      className={
        isActive
          ? "desktop-onboarding-device-card is-active"
          : "desktop-onboarding-device-card"
      }
    >
      <div className="desktop-onboarding-device-icon">
        <LaptopMinimal aria-hidden="true" size={18} />
      </div>
      <div className="desktop-onboarding-device-copy">
        <strong>{name}</strong>
        <span>{status}</span>
      </div>
      <div className="desktop-onboarding-device-pulse" />
    </div>
  );
}

function SessionsPreview() {
  return (
    <div className="desktop-onboarding-session-list">
      <PreviewSessionRow
        meta="2 min ago"
        status="Live"
        title="Investigate CI flake"
      />
      <PreviewSessionRow
        meta="18 min ago"
        status="Waiting"
        title="Review onboarding copy and flow"
      />
      <PreviewSessionRow
        meta="Yesterday"
        status="Done"
        title="Tighten repository routing"
      />
    </div>
  );
}

function PreviewSessionRow({
  meta,
  status,
  title,
}: {
  meta: string;
  status: string;
  title: string;
}) {
  return (
    <div className="desktop-onboarding-session-row">
      <div className="desktop-onboarding-session-icon">
        <MessagesSquare aria-hidden="true" size={16} />
      </div>
      <div className="desktop-onboarding-session-copy">
        <strong>{title}</strong>
        <span>{meta}</span>
      </div>
      <div className="desktop-onboarding-session-badge">{status}</div>
    </div>
  );
}
