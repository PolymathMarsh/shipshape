# HANDOFF: Shipshape

This is for an agent or maintainer arriving with no context. `README.md` covers what Shipshape is and how users install it. This file covers how it's built and maintained.

## What it is
Shipshape is a Claude Code plugin with one skill, `/shipshape`, and three modes:
- **full:** interview, spec, tests first, build, verify, review. Up to 3 rounds.
- **quick:** short spec, 1 round.
- **redline:** reviews existing work against a spec and makes no edits.

The review runs on a different model family when one is available. The plugin has no hooks, no MCP servers and no network code of its own.

## Layout
| Path | Role |
|---|---|
| `.claude-plugin/marketplace.json` | Marketplace entry (name `shipshape`, holds the version) |
| `plugins/shipshape/.claude-plugin/plugin.json` | Plugin manifest (also holds the version; keep the two in sync) |
| `plugins/shipshape/skills/shipshape/SKILL.md` | The loop, 10 steps: setup → reviewer choice and consent → spec → tests → build → verify → review (secrets gate) → triage → risk floor → cap → report |
| `plugins/shipshape/skills/shipshape/reviewers.md` | The exact command for each reviewer CLI (agy, gemini, codex, copilot, ollama, Claude subagent) |
| `plugins/shipshape/skills/shipshape/scan-secrets.sh` | The secrets gate, run on every prompt before any external send; prints file, line number and kind, never the matched text |
| `tests/run.sh` | Scanner tests, about 45 checks; the `repo-self-clean` check scans the whole repo |
| `specs/scan-secrets-multi.md` | The spec for the multi-file scanner, with owner-approved amendments that are dated inline |
| `.github/workflows/checks.yml` | CI: tests on ubuntu, macos and windows, plus a checksum-verified gitleaks CLI scan of the full history |
| `.gitleaksignore` | One entry: a historical fake private key in the root commit's test file |

## Key decisions
- **Repo name is lowercase `shipshape`; prose says Shipshape.**
- **Reviewer order:** agy → gemini → codex → copilot → ollama → Claude subagent. Only **agy** is tested end to end. Gemini CLI is left "untested" on purpose, because personal-account sign-in was shut off. Don't mark a reviewer tested without a real run.
- **External reviewers need consent.** That comes from any one of: a `shipshape: external-review ok` line in the project's CLAUDE.md, an allow-list in `~/.claude/shipshape.local.md`, or `--external` (which asks once and shows the size).
- **The secrets gate always runs.** There is no skip flag, and any non-zero exit blocks the send.
  - Exit codes: 0 clean, 1 possible secret, 2 usage or scan error. Exit 2 having two meanings is accepted.
- **Reviewers run from an empty temp folder.** The prompt uses random-tag section headers and repeats its instructions at the end. Review output is untrusted, and commands in it are never run.
- **Scanner portability:** bash plus POSIX `tr`/`cut` plus `grep -E`/`-a`. No sed, no `grep -P`. `LC_ALL=C`, `printf` (not `echo`), xtrace forced off.
- **No literal fake secrets in the repo.** Split them in the source so they only join up at runtime, e.g. `"Pass""word="`. `repo-self-clean` fails otherwise.
- **Commits:** Conventional Commits. The author email is the GitHub noreply address, set per repo.

## Release procedure
1. Edit the code, then run `bash tests/run.sh`. Expect 0 FAIL. On Windows, 2 skips are normal (`xpg-echo-name`, `unreadable-file`). CI skips `turkish-locale` on Ubuntu.
2. Bump `"version"` in **both** JSON manifests.
3. Commit, then push to `main`. **Changes under `.github/workflows/`:** the maintainer's `gh` token lacks the `workflow` scope, so those are pushed through GitHub Desktop.
4. Check CI: `gh run list -L1`, then `gh run view <id>`. All four jobs must be green.
5. Update the local install: `claude plugin marketplace update shipshape` then `claude plugin update shipshape@shipshape`, then restart Claude Code.

## Redline procedure (reviewing the scanner work)
1. Diff from the last **reviewed** commit: currently `b29f0d1` (0.2.5). Version 0.2.6 (`764a01a`) has not been reviewed.
2. Build the prompt in a fresh temp folder: the spec, the diff (excluding the JSON manifests), the full `scan-secrets.sh`, and local test and CI output.
   - **Keep it under about 28 KB**, because agy takes the prompt as a command-line argument and Windows limits its length.
3. Run `scan-secrets.sh` on the prompt file first. It must say clean.
4. Ask for consent before every external send, even when the reviewer is already set up.
5. Run agy and a fresh read-only Claude review (Plan agent, strongest model) in parallel.
   - agy needs `GEMINI_CLI_TRUST_WORKSPACE=true` and a closed stdin (`</dev/null`), or it hangs.
   - Reviewers have made up commit SHAs before (Gemini did once), so check any SHA they quote.
6. Check every finding against the code before acting on it. Then delete the temp folder.

**Already rejected, don't re-raise as new findings:**
- PATH trust
- FIFO/TOCTOU file swap
- 13 greps per file
- `$*` in `say()`
- C1 control bytes
- "(1 files)" grammar
- exit 2 having two meanings
- `-a` on huge binaries
- platform-dependent test skips
- echo flag injection
- gemini `-p` deprecation
- `--approval-mode plan`

## History (scanner)
- 0.2.0: multi-file scanning with a summary line.
- 0.2.1: matched text kept out of variables and traces; binary files are scanned.
- 0.2.2: `LC_ALL=C`, `printf`, fail closed on any pipe failure; fixtures split.
- 0.2.3: scan errors say what failed.
- 0.2.4: a grep error wins over a cut/tr error; no partial output; whole-repo self-scan.
- 0.2.5: file names are quoted in all output.
- 0.2.6: the self-scan covers untracked files and odd names; test-harness fixes.

## Open items
- `turkish-locale` skips on Ubuntu CI. Fix it by adding `locale-gen tr_TR.UTF-8` to the workflow, pushed through GitHub Desktop.
- **Full mode has never been trialled on a real task.** Only quick and redline have.
- **codex, copilot and ollama are untested.** Their calls follow each tool's docs but have never been run.
