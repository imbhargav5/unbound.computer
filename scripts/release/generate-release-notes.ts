#!/usr/bin/env tsx
/**
 * Generates release notes from commits between the last tag and HEAD.
 * Groups commits by type (feat, fix, chore, etc.) and formats them for GitHub releases.
 *
 * Usage:
 *   tsx generate-release-notes.ts [new-version]
 *
 * Output (stdout):
 *   Markdown-formatted release notes
 */

import { execSync } from "node:child_process";

interface Commit {
  hash: string;
  shortHash: string;
  subject: string;
  type: string | null;
  scope: string | null;
  description: string;
  author: string;
}

const COMMIT_TYPES: Record<string, string> = {
  feat: "Features",
  fix: "Bug Fixes",
  docs: "Documentation",
  style: "Styles",
  refactor: "Code Refactoring",
  perf: "Performance Improvements",
  test: "Tests",
  build: "Build System",
  ci: "CI/CD",
  chore: "Chores",
  revert: "Reverts",
};

function getLastTag(): string | null {
  try {
    const tag = execSync("git describe --tags --abbrev=0 2>/dev/null", {
      encoding: "utf-8",
    }).trim();
    return tag || null;
  } catch {
    return null;
  }
}

function getCommitsSinceTag(tag: string | null): Commit[] {
  const range = tag ? `${tag}..HEAD` : "HEAD";

  // Format: hash|shortHash|subject|author
  const format = "%H|%h|%s|%an";

  try {
    const output = execSync(`git log ${range} --pretty=format:"${format}"`, {
      encoding: "utf-8",
    }).trim();

    if (!output) {
      return [];
    }

    return output.split("\n").map((line) => {
      const [hash, shortHash, subject, author] = line.split("|");

      // Parse conventional commit format: type(scope): description
      const conventionalMatch = subject.match(
        /^(\w+)(?:\(([^)]+)\))?:\s*(.+)$/
      );

      if (conventionalMatch) {
        return {
          hash,
          shortHash,
          subject,
          type: conventionalMatch[1].toLowerCase(),
          scope: conventionalMatch[2] || null,
          description: conventionalMatch[3],
          author,
        };
      }

      return {
        hash,
        shortHash,
        subject,
        type: null,
        scope: null,
        description: subject,
        author,
      };
    });
  } catch {
    return [];
  }
}

function getRepoUrl(): string {
  try {
    const remoteUrl = execSync("git remote get-url origin", {
      encoding: "utf-8",
    }).trim();

    // Convert SSH URL to HTTPS
    if (remoteUrl.startsWith("git@github.com:")) {
      return remoteUrl
        .replace("git@github.com:", "https://github.com/")
        .replace(/\.git$/, "");
    }

    // Already HTTPS
    return remoteUrl.replace(/\.git$/, "");
  } catch {
    return "";
  }
}

function formatReleaseNotes(
  commits: Commit[],
  newVersion: string | null,
  lastTag: string | null
): string {
  const repoUrl = getRepoUrl();

  // Filter out release-related commits
  const relevantCommits = commits.filter((commit) => {
    const lowerSubject = commit.subject.toLowerCase();
    return !(
      lowerSubject.includes("release v") ||
      lowerSubject.includes("cleanup release files") ||
      lowerSubject.startsWith("merge pull request") ||
      lowerSubject.includes("omnara checkpoint")
    );
  });

  if (relevantCommits.length === 0) {
    return "No changes in this release.";
  }

  // Group commits by type
  const grouped: Record<string, Commit[]> = {};

  for (const commit of relevantCommits) {
    const typeKey = commit.type || "other";
    if (!grouped[typeKey]) {
      grouped[typeKey] = [];
    }
    grouped[typeKey].push(commit);
  }

  // Build release notes
  const lines: string[] = [];

  // Add grouped sections
  const typeOrder = Object.keys(COMMIT_TYPES);
  const sortedTypes = Object.keys(grouped).sort((a, b) => {
    const aIndex = typeOrder.indexOf(a);
    const bIndex = typeOrder.indexOf(b);
    if (aIndex === -1 && bIndex === -1) {
      return 0;
    }
    if (aIndex === -1) {
      return 1;
    }
    if (bIndex === -1) {
      return -1;
    }
    return aIndex - bIndex;
  });

  for (const type of sortedTypes) {
    const typeCommits = grouped[type];
    const sectionTitle = COMMIT_TYPES[type] || "Other Changes";

    lines.push(`## ${sectionTitle}`);
    lines.push("");

    for (const commit of typeCommits) {
      const scope = commit.scope ? `**${commit.scope}:** ` : "";
      const commitLink = repoUrl
        ? `([${commit.shortHash}](${repoUrl}/commit/${commit.hash}))`
        : `(${commit.shortHash})`;

      lines.push(`- ${scope}${commit.description} ${commitLink}`);
    }

    lines.push("");
  }

  // Add full changelog link
  if (repoUrl && lastTag && newVersion) {
    lines.push("---");
    lines.push("");
    lines.push(
      `**Full Changelog**: [${lastTag}...v${newVersion}](${repoUrl}/compare/${lastTag}...v${newVersion})`
    );
  }

  return lines.join("\n");
}

function main() {
  const newVersion = process.argv[2] || null;

  const lastTag = getLastTag();
  const commits = getCommitsSinceTag(lastTag);

  const releaseNotes = formatReleaseNotes(commits, newVersion, lastTag);

  console.log(releaseNotes);
}

main();
