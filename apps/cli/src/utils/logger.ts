import chalk from "chalk";
import { config } from "../config.js";

type LogLevel = "debug" | "info" | "warn" | "error";

const levels: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const currentLevel = levels[config.logLevel];

function formatMessage(level: LogLevel, message: string): string {
  const timestamp = new Date().toISOString();
  const prefix = {
    debug: chalk.gray("[DEBUG]"),
    info: chalk.blue("[INFO]"),
    warn: chalk.yellow("[WARN]"),
    error: chalk.red("[ERROR]"),
  }[level];

  return `${chalk.gray(timestamp)} ${prefix} ${message}`;
}

export const logger = {
  debug(message: string, ...args: unknown[]): void {
    if (levels.debug >= currentLevel) {
      console.log(formatMessage("debug", message), ...args);
    }
  },

  info(message: string, ...args: unknown[]): void {
    if (levels.info >= currentLevel) {
      console.log(formatMessage("info", message), ...args);
    }
  },

  warn(message: string, ...args: unknown[]): void {
    if (levels.warn >= currentLevel) {
      console.warn(formatMessage("warn", message), ...args);
    }
  },

  error(message: string, ...args: unknown[]): void {
    if (levels.error >= currentLevel) {
      console.error(formatMessage("error", message), ...args);
    }
  },
};
