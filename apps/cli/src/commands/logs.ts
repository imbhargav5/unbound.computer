import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createInterface } from "node:readline";
import chalk from "chalk";
import { paths } from "../config.js";

interface LogsOptions {
  follow?: boolean;
  lines?: number;
}

/**
 * Logs command - view daemon logs
 */
export async function logsCommand(options: LogsOptions): Promise<void> {
  const { follow = false, lines = 50 } = options;

  try {
    // Check if log file exists
    await stat(paths.daemonLog);
  } catch {
    console.log(chalk.yellow("No log file found."));
    console.log("The daemon may not have been started yet.\n");
    return;
  }

  if (follow) {
    console.log(chalk.gray(`Tailing ${paths.daemonLog}...\n`));
    console.log(chalk.gray("Press Ctrl+C to stop.\n"));

    // For follow mode, use tail -f equivalent
    await tailFollow(paths.daemonLog, lines);
  } else {
    // Read last N lines
    const logLines = await readLastLines(paths.daemonLog, lines);

    if (logLines.length === 0) {
      console.log(chalk.gray("Log file is empty."));
    } else {
      for (const line of logLines) {
        console.log(formatLogLine(line));
      }
    }
  }
}

/**
 * Read last N lines from a file
 */
async function readLastLines(
  filePath: string,
  numLines: number
): Promise<string[]> {
  const allLines: string[] = [];

  const rl = createInterface({
    input: createReadStream(filePath),
    crlfDelay: Number.POSITIVE_INFINITY,
  });

  for await (const line of rl) {
    allLines.push(line);
    if (allLines.length > numLines) {
      allLines.shift();
    }
  }

  return allLines;
}

/**
 * Follow log file (tail -f)
 */
async function tailFollow(
  filePath: string,
  initialLines: number
): Promise<void> {
  const { spawn } = await import("node:child_process");

  return new Promise((resolve, reject) => {
    const tail = spawn("tail", ["-f", "-n", String(initialLines), filePath]);

    tail.stdout.on("data", (data) => {
      const lines = data.toString().split("\n");
      for (const line of lines) {
        if (line.trim()) {
          console.log(formatLogLine(line));
        }
      }
    });

    tail.stderr.on("data", (data) => {
      console.error(chalk.red(data.toString()));
    });

    tail.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`tail exited with code ${code}`));
      }
    });

    // Handle Ctrl+C
    process.on("SIGINT", () => {
      tail.kill();
      console.log("\n");
      resolve();
    });
  });
}

/**
 * Format a log line with colors
 */
function formatLogLine(line: string): string {
  // Try to parse JSON log format
  try {
    const log = JSON.parse(line) as Record<string, unknown>;
    const level = String(log.level || "info");
    const message = String(log.msg || log.message || line);
    const timestamp = log.time
      ? new Date(log.time as string | number).toLocaleTimeString()
      : "";

    const levelColors: Record<string, typeof chalk.gray> = {
      debug: chalk.gray,
      info: chalk.blue,
      warn: chalk.yellow,
      error: chalk.red,
    };

    const levelColor = levelColors[level] || chalk.white;

    return `${chalk.gray(timestamp)} ${levelColor(`[${level.toUpperCase()}]`)} ${message}`;
  } catch {
    // Plain text log
    return line;
  }
}
