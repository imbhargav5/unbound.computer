import { Moon, Sun } from "lucide-react";
import { ThemeSwitchClient } from "./theme-switch-client";

export function ThemeSwitch() {
  return <ThemeSwitchClient />;
}

export function ThemeSwitchFallback() {
  return (
    <div className="relative flex h-6 w-6 items-center justify-center opacity-50">
      <Sun className="dark:-rotate-90 absolute h-full w-full rotate-0 scale-100 transition-all dark:scale-0" />
      <Moon className="absolute h-full w-full rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
    </div>
  );
}
