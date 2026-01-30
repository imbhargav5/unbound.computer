type Pricing = {
  title: string;
  price: string;
  annualPrice: string;
  features: string[];
  description: string;
  isHighlighted?: boolean;
};

export const pricing: Pricing[] = [
  {
    title: "Free",
    price: "0",
    annualPrice: "0",
    description: "For personal projects",
    features: [
      "1 registered device",
      "3 registered repositories",
      "Basic session management",
      "End-to-end encryption",
      "Community support",
    ],
  },
  {
    title: "Pro",
    price: "19",
    annualPrice: "190",
    description: "For individual developers",
    features: [
      "Unlimited devices",
      "Unlimited repositories",
      "Git worktree support",
      "Session history & analytics",
      "Priority relay servers",
      "Email support",
    ],
    isHighlighted: true,
  },
  {
    title: "Team",
    price: "49",
    annualPrice: "490",
    description: "For development teams",
    features: [
      "Everything in Pro",
      "Team management",
      "Shared repository access",
      "Audit logs",
      "SSO integration",
      "Dedicated support",
      "Custom relay deployment",
    ],
  },
];
