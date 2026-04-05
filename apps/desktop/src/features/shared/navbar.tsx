import { type ReactNode, useEffect, useRef, useState } from "react";

/* ------------------------------------------------------------------ */
/*  Icons (inline SVGs matching the Figma design)                      */
/* ------------------------------------------------------------------ */

function PanelLeftIcon() {
  return (
    <svg
      fill="none"
      height="16"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.5"
      viewBox="0 0 24 24"
      width="16"
    >
      <rect height="18" rx="2" width="18" x="3" y="3" />
      <line x1="9" x2="9" y1="3" y2="21" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg
      fill="none"
      height="12"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="12"
    >
      <circle cx="11" cy="11" r="8" />
      <line x1="21" x2="16.65" y1="21" y2="16.65" />
    </svg>
  );
}

function ChevronDownIcon() {
  return (
    <svg
      fill="none"
      height="10"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="10"
    >
      <polyline points="6 9 12 15 18 9" />
    </svg>
  );
}

function MonitorIcon() {
  return (
    <svg
      fill="none"
      height="14"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="14"
    >
      <rect height="14" rx="2" width="20" x="2" y="3" />
      <line x1="8" x2="16" y1="21" y2="21" />
      <line x1="12" x2="12" y1="17" y2="21" />
    </svg>
  );
}

function MessageSquareIcon() {
  return (
    <svg
      fill="none"
      height="12"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="12"
    >
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>
  );
}

function XIcon() {
  return (
    <svg
      fill="none"
      height="14"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="14"
    >
      <line x1="18" x2="6" y1="6" y2="18" />
      <line x1="6" x2="18" y1="6" y2="18" />
    </svg>
  );
}

function ArrowRightIcon() {
  return (
    <svg
      fill="none"
      height="12"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="12"
    >
      <line x1="5" x2="19" y1="12" y2="12" />
      <polyline points="12 5 19 12 12 19" />
    </svg>
  );
}

/* ------------------------------------------------------------------ */
/*  Search Bar                                                         */
/* ------------------------------------------------------------------ */

interface NavbarSearchBarProps {
  expanded: boolean;
  onExpand: () => void;
  onCollapse: () => void;
  placeholder?: string;
}

function NavbarSearchBar({
  expanded,
  onExpand,
  onCollapse,
  placeholder = "Search tasks, repos...",
}: NavbarSearchBarProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [activeIndex, setActiveIndex] = useState(0);

  useEffect(() => {
    if (expanded && inputRef.current) {
      inputRef.current.focus();
    }
  }, [expanded]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        if (expanded) {
          onCollapse();
        } else {
          onExpand();
        }
      }

      if (e.key === "Escape" && expanded) {
        onCollapse();
        setQuery("");
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [expanded, onExpand, onCollapse]);

  const mockResults = query.trim()
    ? [
        {
          kind: "issue" as const,
          label: `Fix build pipeline for "${query}"`,
          tag: "UNB-142",
        },
        {
          kind: "repo" as const,
          label: `unbound-${query.toLowerCase().replaceAll(" ", "-")}`,
          tag: "Repository",
        },
        {
          kind: "session" as const,
          label: `Session: ${query} refactor`,
          tag: "Active",
        },
      ]
    : [];

  if (!expanded) {
    return (
      <button
        className="navbar-search-trigger"
        onClick={onExpand}
        type="button"
      >
        <SearchIcon />
        <span className="navbar-search-placeholder">{placeholder}</span>
        <kbd className="navbar-kbd">
          <span>K</span>
        </kbd>
      </button>
    );
  }

  return (
    <div className="navbar-search-expanded">
      <div className="navbar-search-overlay" onClick={onCollapse} />
      <div className="navbar-search-dialog">
        <div className="navbar-search-input-row">
          <SearchIcon />
          <input
            className="navbar-search-input"
            onChange={(e) => {
              setQuery(e.target.value);
              setActiveIndex(0);
            }}
            placeholder={placeholder}
            ref={inputRef}
            type="text"
            value={query}
          />
          <button
            className="navbar-search-close"
            onClick={() => {
              onCollapse();
              setQuery("");
            }}
            type="button"
          >
            <span className="navbar-kbd-inline">esc</span>
          </button>
        </div>

        {mockResults.length > 0 ? (
          <div className="navbar-search-results">
            {mockResults.map((result, i) => (
              <button
                className={
                  i === activeIndex
                    ? "navbar-search-result active"
                    : "navbar-search-result"
                }
                key={result.label}
                onMouseEnter={() => setActiveIndex(i)}
                type="button"
              >
                <span className="navbar-search-result-label">
                  {result.label}
                </span>
                <span className="navbar-search-result-tag">{result.tag}</span>
                {i === activeIndex ? (
                  <span className="navbar-search-result-enter">
                    <ArrowRightIcon />
                  </span>
                ) : null}
              </button>
            ))}
          </div>
        ) : query.trim() ? (
          <div className="navbar-search-empty">No results for "{query}"</div>
        ) : (
          <div className="navbar-search-hints">
            <span className="navbar-search-hint-label">Quick actions</span>
            <div className="navbar-search-hint-row">
              <kbd className="navbar-kbd-inline">#</kbd>
              <span>Search issues</span>
            </div>
            <div className="navbar-search-hint-row">
              <kbd className="navbar-kbd-inline">/</kbd>
              <span>Search repositories</span>
            </div>
            <div className="navbar-search-hint-row">
              <kbd className="navbar-kbd-inline">@</kbd>
              <span>Search sessions</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Navbar                                                             */
/* ------------------------------------------------------------------ */

export interface NavbarProps {
  deviceName?: string;
  onToggleSidebar?: () => void;
  onFeedback?: () => void;
}

export function Navbar({
  deviceName = "MacBook Pro",
  onToggleSidebar,
  onFeedback,
}: NavbarProps) {
  const [searchExpanded, setSearchExpanded] = useState(false);

  return (
    <header className="navbar">
      {/* Left: sidebar toggle + device selector */}
      <div className="navbar-left">
        <button
          className="navbar-icon-button"
          onClick={onToggleSidebar}
          title="Toggle sidebar"
          type="button"
        >
          <PanelLeftIcon />
        </button>
        <button className="navbar-device-selector" type="button">
          <MonitorIcon />
          <span className="navbar-device-name">{deviceName}</span>
          <ChevronDownIcon />
        </button>
      </div>

      {/* Center: search */}
      <div className="navbar-center">
        <NavbarSearchBar
          expanded={searchExpanded}
          onCollapse={() => setSearchExpanded(false)}
          onExpand={() => setSearchExpanded(true)}
        />
      </div>

      {/* Right: feedback */}
      <div className="navbar-right">
        <button
          className="navbar-feedback-button"
          onClick={onFeedback}
          type="button"
        >
          <MessageSquareIcon />
          <span>Give Feedback</span>
        </button>
      </div>
    </header>
  );
}
