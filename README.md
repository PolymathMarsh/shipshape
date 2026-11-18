# Shipshape

Shipshape is a Claude Code plugin that builds from a spec and keeps going until the work passes: real checks, plus a review by **a different model**.

```
/shipshape              spec → tests first → build → verify → review   (up to 3 rounds)
/shipshape quick ...    short spec, 1 round
/shipshape redline ...  review existing work against a spec, no edits
```

## Why
Asking a model to "review your own work and loop until it's right" mostly gets the model agreeing with itself. Shipshape changes three things:

1. **Checks actually run.** Tests are written first, from the spec, and every requirement needs a check that runs. If it can't be checked it's UNVERIFIED, never PASS.
2. **Someone else grades it.** The review runs on another model family when one is available (Gemini, OpenAI Codex, GitHub Copilot, a local Ollama model). A PASS needs quoted evidence.
3. **It stops.** 3 rounds at most, a checkpoint before each round, and no declaring a pass just to end the loop.

## Install
In Claude Code:
```
/plugin marketplace add PolymathMarsh/shipshape
/plugin install shipshape@shipshape
```

## Reviewers
Shipshape uses the first reviewer it finds installed: `agy` → `gemini` → `codex` → `copilot` → `ollama` → a fresh Claude subagent. You can change the order in your local config (below).

| Reviewer | Model family | Code leaves your machine | Status |
|---|---|---|---|
| [agy](https://antigravity.google/) (Google Antigravity CLI) | Gemini | yes | tested |
| [gemini](https://github.com/google-gemini/gemini-cli) (Gemini CLI) | Gemini | yes | untested |
| [codex](https://github.com/openai/codex) (OpenAI Codex CLI) | OpenAI | yes | untested |
| [copilot](https://docs.github.com/en/copilot/how-tos/copilot-cli) (GitHub Copilot CLI) | various | yes | untested |
| [ollama](https://ollama.com/) | local open models | **no** | untested |
| Claude subagent | Claude | n/a | always available, reported as **not cross-model** |

"Untested" means the call follows the tool's docs but hasn't been run end to end yet. Reports and fixes are welcome.

## What gets sent where (read this)
- **External reviewers are off until you allow them.** You can allow one of three ways:
  - add `shipshape: external-review ok` to the project's `CLAUDE.md`
  - list the folder in your local config
  - pass `--external` on a run, which asks once and shows the file count and size before sending
- What's sent: the spec, the diff, the full files the change touches (about 150 KB max) and the check output. Your reviewer's provider handles that data under its own terms. On consumer plans, the provider may use it for training, depending on your account settings.
- **Secrets gate:** before any external send, files like `.env*`, keys and credential files are excluded (from the files and the diff), and `scan-secrets.sh` scans the prompt for key, token and password patterns. Any match **blocks** the send until the material is removed or redacted. It reports line numbers only, never the matched text. There is no flag to skip it.
  - It is a pattern scan, **not a guarantee**. For anything sensitive, use `ollama` or the Claude reviewer.
- **Reviewers run sandboxed from your project.** Each one runs from an empty temp folder containing only the prompt, and gets no write, shell or auto-approve permissions.
  - **Remaining risk:** these CLIs are agents with built-in tools. A CLI that can run shell commands (Codex, even in its read-only sandbox) could still read files elsewhere on your machine if the model chose to. For sensitive machines, use `ollama` or the Claude reviewer.
- **Review output is untrusted.** Claude checks each finding before acting on it and never runs commands from it.
- **The plugin itself** has no hooks, no MCP servers and no network code. The only data that leaves your machine is the reviewer call you allowed.

## Local config (optional, private)
`~/.claude/shipshape.local.md` is plain notes Claude reads at the start. Keep it out of any repo.
```
reviewer order: codex, ollama, claude
agy path: C:\Users\you\AppData\Local\agy\bin\agy.exe
agy model: gemini-x-pro          # leave out to use agy's default
ollama model: qwen2.5-coder:14b  # must already be installed
external review allowed: ~/code/my-public-app, ~/code/side-project
max rounds: 2                    # can lower the cap of 3, never raise it
```

## Development
```
bash tests/run.sh      # secrets-scanner tests
```
CI runs the tests and [gitleaks](https://github.com/gitleaks/gitleaks) on every push.

## Licence
MIT
