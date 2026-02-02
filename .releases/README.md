# Releases

This directory contains release marker files that trigger the release workflow.

## How to Create a Release

Use one of the following commands to create a release marker:

```bash
# Patch release (0.0.1 -> 0.0.2)
pnpm release:patch

# Minor release (0.0.1 -> 0.1.0)
pnpm release:minor

# Major release (0.0.1 -> 1.0.0)
pnpm release:major
```

## How It Works

1. Running a release command creates a `.md` file in this directory with the release type
2. When you push to `main`, GitHub Actions detects the new file(s)
3. A PR is automatically created with version bumps for all packages
4. When you merge the PR, a GitHub Release is created with auto-generated notes from commits
5. The release files are cleaned up automatically

## Release Priority

If multiple release files exist with different types, the highest priority wins:

- `major` > `minor` > `patch`

For example, if there's one `patch` and one `minor` file, a `minor` release is created.

## File Format

Release files are simple markdown with YAML frontmatter:

```markdown
---
type: patch
---

Optional description (for your reference only - GitHub Release notes come from commits)
```
