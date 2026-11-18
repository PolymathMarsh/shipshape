# shipshape reviewers

Detect each one with `command -v <tool>`, or use a path set in `~/.claude/shipshape.local.md`.
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
| agy (Google Antigravity CLI) | Gemini | yes | argument (≈28 KB max on Windows) | tested |
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

## agy
```
GEMINI_CLI_TRUST_WORKSPACE=true agy ${AGY_MODEL:+--model "$AGY_MODEL"} --print-timeout 9m -p "$(cat "$P")" </dev/null > "$OUT" 2>"$OUT.err"
```
Set `AGY_MODEL` from the local config's agy model, if one is given; otherwise agy uses its default.
`agy models </dev/null` lists the ids. Without the env var and the closed stdin, agy hangs with no
output. It also hangs if it needs an interactive sign-in: tell the user to run `agy` once in a terminal.

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
