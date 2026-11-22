# GitHub Copilot instructions

## Before changing code

- Check `git status --short --branch` and the current branch before editing. Preserve all user changes; never reset, discard, or overwrite uncommitted work.
- Never develop directly on `main` or `develop`. Use descriptive temporary branches.
- Identify the task type and its correct base:
  - Feature: create `feature/<short-description>` from `develop`.
  - Development bug fix: create `bugfix/<short-description>` from `develop`.
  - Release stabilization: create `release/<version>` from `develop`.
  - Production hotfix: create `hotfix/<short-description>` from `main`.
- If the required base branch is unavailable, or the current branch conflicts with these rules, stop and ask before creating a branch from another base.
- Do not assume that opening a new Copilot chat creates or switches a Git branch.

## Local Copilot and Coding Agent

- A local Copilot Chat session works in the branch and worktree already checked out by the developer. It does not create, select, push, merge, or delete branches unless the developer explicitly requests those operations.
- GitHub Copilot Coding Agent works in a GitHub-managed branch/worktree and normally proposes its changes as a pull request. Confirm the task's intended base and branch policy; do not assume that a new agent task follows the same branch context as a local chat.
- In either workflow, inspect the actual Git branch before editing and follow the feature, bugfix, release, or hotfix base above.

## Pull requests and releases

- Run the relevant tests before preparing a pull request. For application or delivery behavior changes, add a focused release-note entry under `.github/release-notes/`.
- Use the repository pull request template and a descriptive Conventional Commit title.
- Never merge or delete branches without explicit authorization.
- Never publish, tag, or promote a beta, release candidate, or stable release without explicit authorization.
- Preserve the configured target in `.github/release-config.json`; never infer the next release version from a branch name.
- Do not rebuild an unchanged image during promotion. Promote its existing digest, verify the digest before and after, and keep immutable build identity separate from the promoted channel version.
- Do not add Docker socket access or automatic container replacement to application update checks.
