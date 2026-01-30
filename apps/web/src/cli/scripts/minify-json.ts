#!/usr/bin/env node

import { editor } from "@inquirer/prompts";
import { execSync } from "child_process";
import { readFileSync } from "fs";
import { resolve } from "path";

/**
 * Copies text to clipboard
 */
function copyToClipboard(text: string): boolean {
  try {
    if (process.platform === "darwin") {
      // macOS
      execSync("pbcopy", { input: text });
    } else if (process.platform === "win32") {
      // Windows
      execSync("clip", { input: text });
    } else {
      // Linux
      execSync("xclip -selection clipboard", { input: text });
    }
    return true;
  } catch {
    return false;
  }
}

/**
 * Processes and minifies JSON content
 */
function processJson(content: string): void {
  try {
    // Parse and minify (removes all whitespace)
    const parsed = JSON.parse(content);
    const minified = JSON.stringify(parsed);

    // Copy to clipboard
    const copied = copyToClipboard(minified);

    if (copied) {
      console.log("\n✓ JSON minified and copied to clipboard!");
    } else {
      console.log(
        "\n✓ JSON minified (clipboard copy failed, outputting below):"
      );
      console.log("\n" + minified);
    }

    console.log(`\nOriginal size: ${content.length} bytes`);
    console.log(`Minified size: ${minified.length} bytes`);
    console.log(
      `Saved: ${content.length - minified.length} bytes (${Math.round((1 - minified.length / content.length) * 100)}%)`
    );
  } catch (error) {
    if (error instanceof SyntaxError) {
      console.error("\n❌ Error: Invalid JSON");
      console.error(error.message);
    } else if (error instanceof Error) {
      console.error("\n❌ Error:", error.message);
    } else {
      console.error("\n❌ Error: An unknown error occurred");
    }
    process.exit(1);
  }
}

/**
 * Minifies a JSON file or prompts for JSON input
 */
async function minifyJson() {
  const args = process.argv.slice(2);

  // If file path is provided, use it
  if (args.length > 0) {
    const filePath = resolve(process.cwd(), args[0]);
    try {
      const fileContent = readFileSync(filePath, "utf-8");
      processJson(fileContent);
    } catch (error) {
      if (error instanceof Error) {
        if ("code" in error && error.code === "ENOENT") {
          console.error(`❌ Error: File not found: ${filePath}`);
        } else {
          console.error("❌ Error:", error.message);
        }
      }
      process.exit(1);
    }
  } else {
    // Prompt for JSON input
    console.log("Paste your JSON below (editor will open):");
    const jsonInput = await editor({
      message: "Paste your JSON here",
      default: "",
      waitForUserInput: false,
    });

    if (!jsonInput.trim()) {
      console.error("\n❌ Error: No JSON provided");
      process.exit(1);
    }

    processJson(jsonInput);
  }
}

minifyJson();
