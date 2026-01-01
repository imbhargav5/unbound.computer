#!/usr/bin/env node

import { Command } from "commander";
import { credentials } from "./auth/index.js";
import {
  linkCommand,
  listCommand,
  logsCommand,
  registerCommand,
  statusCommand,
  unlinkCommand,
  unregisterCommand,
  webAuthorizeCommand,
} from "./commands/index.js";

const program = new Command();

program
  .name("unbound")
  .description("Unbound CLI - Remote Claude Code sessions from your phone")
  .version("0.0.1");

// Link command - initial setup
program
  .command("link")
  .description("Set up Unbound CLI: authenticate and register this device")
  .action(async () => {
    await credentials.init();
    await linkCommand();
  });

// Register command - add current directory as a project
program
  .command("register")
  .description("Register current git repository as a project")
  .action(async () => {
    await credentials.init();
    await registerCommand();
  });

// Unregister command - remove current directory from projects
program
  .command("unregister")
  .description("Unregister current git repository from projects")
  .action(async () => {
    await credentials.init();
    await unregisterCommand();
  });

// List command - show all registered projects
program
  .command("list")
  .alias("ls")
  .description("List all registered projects")
  .action(async () => {
    await credentials.init();
    await listCommand();
  });

// Status command - show daemon status and connection info
program
  .command("status")
  .description("Show daemon status, connection state, and active sessions")
  .action(async () => {
    await credentials.init();
    await statusCommand();
  });

// Logs command - view daemon logs
program
  .command("logs")
  .description("View daemon logs")
  .option("-f, --follow", "Follow log output (like tail -f)", false)
  .option("-n, --lines <number>", "Number of lines to show", "50")
  .action(async (options) => {
    await logsCommand({
      follow: options.follow,
      lines: Number.parseInt(options.lines, 10),
    });
  });

// Unlink command - remove device registration
program
  .command("unlink")
  .description("Unlink this device and remove all stored credentials")
  .action(async () => {
    await credentials.init();
    await unlinkCommand();
  });

// Web Authorize command - authorize a web session
program
  .command("web-authorize")
  .alias("wa")
  .description("Authorize a web session by scanning QR code or pasting data")
  .argument("[qrData]", "QR code data or web session URL (optional)")
  .action(async (qrData?: string) => {
    await credentials.init();
    await webAuthorizeCommand(qrData);
  });

// Start daemon in foreground (for debugging)
program
  .command("start")
  .description("Start the daemon in foreground (for debugging)")
  .action(async () => {
    // Import daemon module dynamically to avoid loading it for other commands
    const { startDaemon } = await import("./daemon.js");
    await startDaemon();
  });

// Default command - start Claude Code in current directory
program
  .command("run", { isDefault: true })
  .description(
    "Start Claude Code session in current directory (continuable on phone)"
  )
  .action(async () => {
    await credentials.init();
    const isLinked = await credentials.isLinked();

    if (!isLinked) {
      console.log("Device not linked. Run 'unbound link' first.");
      process.exit(1);
    }

    // TODO: Implement handoff mode - start Claude Code locally and make it visible on phone
    console.log("Handoff mode not yet implemented.");
    console.log("For now, use 'unbound register' to register this project.");
  });

// Parse and execute
program.parse();
