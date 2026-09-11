---
name: resolve-issue
description: Take a GitHub issue from diagnosis to an open pull request — root cause, fix, local checks, commit, PR. Use when asked to "fix #N", "implement #N", "resolve #N", or "do issue N". Not for filing a new issue.
---

# Resolve an issue

Work one issue, `$ARGUMENTS`, end to end. Every rule in `AGENTS.md` applies; this is the order to apply them in.

1. **Read it.** `gh issue view <N> --comments`. Restate the acceptance criteria in a sentence or two. Check
   `gh pr list --search "<N>"` so you are not duplicating an open PR.
2. **Branch.** `fix/<N>-short-description` or `feat/<N>-short-description` off an up-to-date `main`.
3. **Diagnose before editing.** State the causal chain from user action to symptom and name the line
   responsible. For a bug, write the failing test or scripted repro first and show it failing. Confirm the
   path the issue describes is the one you are about to change.
4. **Find the siblings.** Grep for every other call site, route, file kind, or platform with the same defect,
   and fix them in the shared place.
5. **Implement the minimal fix.** No new abstractions, dependencies, or forks without asking first.
6. **Verify locally.** Re-run the repro and show it passing. Then `gmake check` and the relevant
   `gmake test/...` targets. Regenerate and commit anything `make generate` produces. Add new proper nouns to
   `.vscode/cspell.json`.
7. **Commit.** One focused, signed-off commit (`git commit -s`), conventional-commit subject, American
   spelling, no Claude Code session link.
8. **Open the PR.** Push, then `gh pr create` with a conventional-commit title, `Closes #<N>` in the body,
   and the PR template filled in.
9. **Report.** List exactly what you ran and what it showed. Never claim a manual check you did not perform.
