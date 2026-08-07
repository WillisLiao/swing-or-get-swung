# Workflow - working on Riftline with two developers + AI assistants

This repo (`WillisLiao/chatgtt`, public) is the standalone home for
Riftline / WhoYouPeekin. It was split out of a larger personal monorepo
on 2026-08-06 with fresh history (no old commits carried over).

## 1. Repo access

- Repo is **public** (needed on a personal GitHub account to get free
  branch protection - private-repo branch protection requires GitHub Pro).
- Willis (`WillisLiao`) is the owner/admin. Robert (`robertwu072792`) is a
  collaborator with **write** access - enough to push branches and open
  PRs, not enough to merge past branch protection.
- Default branch: `main`, and it is **protected**: merging requires at
  least 1 approving review. Only Willis (repo admin) can approve/merge -
  this is enforced by GitHub, not just convention.
- Anyone pushing directly to `main` will be rejected by GitHub regardless
  of write access - always work on a branch and open a PR.

## 2. Day-to-day git flow

1. `git pull origin main` before starting.
2. Create a branch per task: `git checkout -b <yourname>/<short-topic>`
   e.g. `robert/bomb-mode-hud`.
3. Commit as you go with real messages (what changed and why, not "wip").
4. Push the branch, open a PR into `main`.
5. The other person reviews (or self-merge for small/solo changes if you
   agree that's fine for a 2-person team - just don't let unreviewed AI
   output pile up on `main`).
6. Delete the branch after merge.

Avoid both people editing `main` directly at the same time - Godot's
`.tscn`/`.tres` files are text and merge reasonably, but scene file
conflicts are still painful to resolve by hand. Branches + PRs sidestep
most of that.

## 3. Godot-specific hygiene

- `.godot/` and `build/` are gitignored - never commit them. Each
  developer's Godot editor regenerates `.godot/` locally on first open.
- Scenes/resources are already text format (`.tscn`/`.tres`), so diffs and
  merges work - keep it that way (don't switch to binary format).
- If you add binary assets (textures, audio) later, consider Git LFS before
  the repo grows large. As of 2026-08-07 the "zero imported art" rule is
  lifted - Blender-authored assets (the character, Cover V2, and now the
  art/UI redesign) are an explicit, ongoing part of the pipeline, not an
  exception. Watch repo size as more binary assets land.
- `export_presets.cfg` is committed (build config, no secrets in it).
  If you ever add signing keys/credentials for export, keep those in
  `export_credentials.cfg` (already gitignored) - never commit them.

## 4. Using Claude Code / Codex as collaborators

Both of you can use your own subscriptions independently - there's no
special integration needed beyond normal git:

- **Each developer runs their own AI assistant locally** (Claude Code,
  Codex CLI, etc.) against their own clone/branch. The assistant reads
  the working tree and git history like any tool; it doesn't need to know
  about the other developer.
- **Context lives in the repo, not in a chat history.** This project
  already uses `devlogs/` (dated session logs) and `handoffs/` (living
  snapshot + bootstrap docs for specific unstarted work). Keep using
  that convention:
  - When an AI session finishes real work, have it append a devlog entry
    and update `handoffs/HANDOFF.md`.
  - When there's a well-scoped chunk of upcoming work, have it write a
    `handoffs/NEXT-SESSION-<topic>.md` with exact commands/tooling paths
    (see the existing `NEXT-SESSION-riftline-modes-art.md` as a template).
  - This means either developer's AI assistant can pick up mid-stream
    work started by the other person's assistant, because the state is
    written down in the repo, not trapped in a chat transcript.
- **PRs are the sync point.** If your AI assistant makes a multi-file
  change, review the diff yourself before opening the PR - treat AI output
  the same as a junior dev's PR, not as pre-approved.
- **Don't let two AI sessions edit the same branch concurrently.** Same
  rule as two humans - one branch, one active editor at a time.
- Optional: use GitHub Issues to track tasks. Both Claude Code and Codex
  can be pointed at an issue number/URL and asked to implement it, which
  gives you a natural handoff unit that's independent of which AI tool
  either of you happens to be subscribed to.

## 5. Suggested first setup steps for your collaborator

1. Accept the GitHub collaborator invite.
2. `git clone https://github.com/WillisLiao/chatgtt.git`
3. Install Godot 4.7 (mobile export templates if building for device).
4. Open `project.godot` once to let the editor regenerate `.godot/`.
5. Read `handoffs/HANDOFF.md` and the most recent `devlogs/` entry to get
   current-state context before making changes.
