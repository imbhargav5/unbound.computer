"use client";

import { Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";

export function ThemeSwitchClient() {
  const { theme, setTheme } = useTheme();
  const handleToggle = () => {
    setTheme(theme === "dark" ? "light" : "dark");
  };

  return (
    <button
      aria-label="Toggle theme"
      className="relative flex h-6 w-6 items-center justify-center"
      onClick={handleToggle}
      type="button"
    >
      <Sun className="dark:-rotate-90 absolute h-full w-full rotate-0 scale-100 transition-all dark:scale-0" />
      <Moon className="absolute h-full w-full rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
    </button>
  );
}
