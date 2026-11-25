# shipshape reviewers

Detect each CLI with `command -v <tool>`, or use a path set in `~/.claude/shipshape.local.md`.
`gemini-api` is detected differently (see its section).
`$P` is the prompt file and `$OUT` is the result file, both inside the review's **empty temp folder**.
`cd` into that folder before every call. Run each call in the background and give it up to 10 minutes.

**Rules for every reviewer**
- Read-only. Never pass flags that grant write, shell or auto-approve access (`--dangerously-*`,
  `--yolo`, `--approval-mode yolo`, `--allow-all-tools`, `--full-auto`).
- Close stdin or pipe the prompt in. Some CLIs hang waiting on an open stdin.
- Keep stderr out of `$OUT` (`2>"$OUT.err"`), so progress bars and escape codes don't mix with the
  review. Show `$OUT.err` to the user only if the call fails.

| Reviewer | Family | Leaves the machine | Prompt via | Status |
|---|---|---|---|---|
| gemini-api (Gemini API, bundled script) | Gemini | yes | request body (no size cap) | tested |
| gemini (Gemini CLI) | Gemini | yes | stdin | untested |
| codex (OpenAI Codex CLI) | OpenAI | yes | stdin | untested |
| copilot (GitHub Copilot CLI) | various | yes | argument (≈28 KB max on Windows) | untested |
| ollama | local open models | **no** | stdin | untested |
| Claude subagent | Claude | n/a | brief | always available, **not cross-model** |

"Untested" means the call follows the tool's documentation but hasn't been run end to end by the
author. If a call fails, show the user the error and try the next reviewer.

**Remaining risk (say so in the README, don't hide it):** agentic CLIs have their own built-in tools.
Running them from an empty folder stops them reading the project, but a CLI that can run shell
commands (codex, even in its read-only sandbox) can still *read* files elsewhere on the machine if
the model decides to. The prompt tells it not to use tools. For sensitive machines, prefer
`ollama` or the Claude subagent.

## gemini-api
Detect: `GEMINI_API_KEY` is set (test with `[ -n "$GEMINI_API_KEY" ]`; never print it) and a
working Python 3.8+ is found. On Windows, `python3` can be the Microsoft Store stub that only prints
"Python was not found", so test each candidate by running it:
```
PY=$(for c in python3 python py; do "$c" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null && { echo "$c"; break; }; done)
```
Available when `$PY` is non-empty. The script is `gemini-api.py` in this skill's folder; it is not
an agent, has no tools, and contacts only the Gemini API (through your HTTPS proxy, if one is set).
```
"$PY" -I "<this skill's folder>/gemini-api.py" "${GEMINI_MODEL:-gemini-4-argon-high}" "$P" "$OUT" 9m 2>"$OUT.err"
```
Set `GEMINI_MODEL` from the local config's gemini model, if one is given. It prints one status line:
`SUCCESS …` (exit 0) or `FAILED …` / `NO KEY …` (exit 1: HTTP error, rate limit or spend cap,
truncated or blocked answer). Treat anything but `SUCCESS` as a failed reviewer and try the next.
The key is billed per token on the user's AI Studio project. On Google's unpaid tier, prompts may be
human-reviewed and used to improve Google's products. Both points go in the one-line reviewer
announcement (SKILL.md step 0), whatever the source of consent.

**Why not `agy` (Google Antigravity CLI):** Google's Antigravity FAQ (checked 25 Nov 2026) says
"Wrapping `agy` inside third-party coding agents or applications … is not supported under consumer
plans". The same FAQ names Claude Code in its heading and says using third-party software to access
Antigravity "can result in suspension or termination of your account". Shipshape never calls `agy`.

## gemini
```
gemini -p "Review the material on stdin exactly as instructed in it. Do not use tools." --approval-mode default < "$P" > "$OUT" 2>"$OUT.err"
```
Stdin is combined with the `-p` text.

## codex
```
codex exec --ephemeral --skip-git-repo-check --sandbox read-only - < "$P" > "$OUT" 2>"$OUT.err"
```
`-` reads the whole prompt from stdin. `--skip-git-repo-check` is needed because the temp folder is
not a git repo.

## copilot
```
copilot -p "$(cat "$P")" --deny-tool='shell' --deny-tool='write' </dev/null > "$OUT" 2>"$OUT.err"
```
This is the standalone GitHub Copilot CLI, not the `gh copilot` extension. Deny rules win over
allow rules. Never add `--allow-all-tools`.

## ollama
Use only a model that is **already installed**: check that `ollama list` shows it. Never let
`ollama run` download a model, because that can be many GB. If the configured model is missing,
tell the user and skip ollama.
```
OLLAMA_CONTEXT_LENGTH=32768 ollama run --nowordwrap "$OLLAMA_MODEL" < "$P" > "$OUT" 2>"$OUT.err"
```
`OLLAMA_CONTEXT_LENGTH` only takes effect if it was set when the Ollama server started. Otherwise the
default context (often 2–8K tokens) will silently cut long prompts. Keep the prompt within the
model's context, or tell the user the review saw only part of it. Small models review weakly: name
the model in the report and treat its PASSes with extra caution.

## Claude subagent (fallback)
An Agent call with a fresh context and a **read-only** agent type (one without Edit, Write or shell
tools, such as Plan or Explore), with the prompt file's content as the brief. Use the strongest
available model. The report must say "not cross-model".
