type FAQ = {
  question: string;
  answer: string;
};

export const faq: FAQ[] = [
  {
    question: "How does end-to-end encryption work?",
    answer:
      "Your mobile device and development machine establish a secure channel using public-key cryptography. The relay server only forwards encrypted messages - it never has access to your code, commands, or session content.",
  },
  {
    question: "What platforms are supported?",
    answer:
      "The Unbound daemon runs on macOS, Linux, and Windows. Mobile apps are available for iOS and Android. The daemon runs as a background service (launchd on Mac, systemd on Linux) and maintains a persistent connection to the relay.",
  },
  {
    question: "How do I register a repository?",
    answer:
      "Run 'unbound register' in any git repository. The CLI detects repo info (name, path, remote URL) and syncs it to your account. The repository then becomes available on your mobile device for starting Claude Code sessions.",
  },
  {
    question: "Can I start a session from my computer and continue on mobile?",
    answer:
      "Yes! Use 'unbound' in any registered directory to start Claude Code in handoff mode. The session immediately appears on your phone, letting you monitor and interact with it remotely.",
  },
  {
    question: "What happens if my internet connection drops?",
    answer:
      "The daemon maintains session state locally. When connectivity is restored, it automatically reconnects to the relay server. Active Claude Code sessions continue running on your machine regardless of network status.",
  },
];
