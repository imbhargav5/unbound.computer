"use client";

interface LocaleSwitcherMobileTabletLinkProps {
  onClick: () => void;
  label: string;
}

export function LocaleSwitcherMobileTabletLink({
  onClick,
  label,
}: LocaleSwitcherMobileTabletLinkProps) {
  return (
    <button
      className="w-full rounded-lg px-4 py-2 text-left text-gray-900 transition-colors hover:bg-accent dark:text-gray-300"
      onClick={onClick}
    >
      {label}
    </button>
  );
}
