//
//  GitAgentPromptFactory.swift
//  unbound-macos
//
//  Prompt templates for sidebar-triggered Git workflows run by the coding agent.
//

import Foundation

enum GitSidebarAgentAction {
    case commit
    case commitAndPush
    case commitRebaseAndPush
    case commitAndCreatePullRequest
    case push
    case rebaseAndPush
    case createPullRequest
}

enum GitAgentPromptFactory {
    static func prompt(for action: GitSidebarAgentAction) -> String {
        switch action {
        case .commit:
            return """
            Execute this Git workflow in the current repository:
            1. Stage all changes with `git add -A` (include staged, unstaged, and untracked files).
            2. Inspect the staged diff and generate a concise, high-quality commit message.
            3. Create exactly one commit.
            4. Reply with: commit message used, short SHA, full SHA, and a short summary.
            If there is nothing to commit, say that explicitly and stop.
            """
        case .commitAndPush:
            return """
            Execute this Git workflow in the current repository:
            1. Stage all changes with `git add -A`.
            2. Generate a concise commit message from the staged diff and create one commit.
            3. Push the current branch to its upstream remote.
            4. Reply with: commit message, commit SHA, pushed remote/branch, and result.
            If there is nothing to commit or nothing to push, say that explicitly.
            """
        case .commitRebaseAndPush:
            return """
            Execute this Git workflow in the current repository:
            1. Stage all changes with `git add -A`.
            2. Generate a concise commit message from the staged diff and create one commit.
            3. Fetch updates from remote and rebase the current branch onto its configured upstream.
            4. If rebase conflicts happen, stop and report conflicted files with resolution guidance.
            5. If rebase succeeds, push the branch to upstream.
            6. Reply with: commit message, commit SHA, rebase status, and push result.
            """
        case .commitAndCreatePullRequest:
            return """
            Execute this Git workflow in the current repository:
            1. Stage all changes with `git add -A`.
            2. Generate a concise commit message from the staged diff and create one commit.
            3. Push the current branch to upstream.
            4. Create a GitHub pull request from the current branch to the repository default base branch.
            5. Use a concise PR title/body derived from the commit(s).
            6. Reply with: commit message, commit SHA, pushed branch, PR number, and PR URL.
            If GitHub auth is missing, explain that clearly.
            """
        case .push:
            return """
            Execute this Git workflow in the current repository:
            1. Verify the current branch and its upstream tracking branch.
            2. Push the current branch to upstream.
            3. Reply with: remote, branch, and push result.
            If there is nothing to push, say that explicitly.
            """
        case .rebaseAndPush:
            return """
            Execute this Git workflow in the current repository:
            1. Verify the current branch and upstream tracking branch.
            2. Fetch latest remote updates.
            3. Rebase current branch onto upstream.
            4. If conflicts occur, stop and report conflicted files plus next steps.
            5. If rebase succeeds, push to upstream.
            6. Reply with: rebase status and push result.
            """
        case .createPullRequest:
            return """
            Execute this Git workflow in the current repository:
            1. Ensure the current branch is available on remote (push first if needed).
            2. Create a GitHub pull request from current branch to default base branch.
            3. Use a concise PR title/body based on recent commits.
            4. Reply with: PR number, PR URL, base branch, and head branch.
            If GitHub auth is missing, explain that clearly.
            """
        }
    }
}
