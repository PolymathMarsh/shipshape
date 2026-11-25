"""Run a prompt file through the Gemini API with the AI Studio key (no agy, no subscription login).

Usage:  python -I gemini-api.py <model-id> <prompt-file> <result-file> [total timeout like 9m or 300s]

Model id: an API id such as gemini-4-argon or gemini-3.8-flash, optionally with a thinking
suffix -low / -medium / -high (e.g. gemini-4-argon-high), which becomes
generationConfig.thinkingConfig.thinkingLevel. If the API rejects the thinking setting, the
call is retried without it and the status line says so.

Key: read only from the GEMINI_API_KEY environment variable (a Google AI Studio API key). It is
sent in the x-goog-api-key header, never in the URL or on a command line, and is never printed or
written to the result file. Standard library only; the only host it contacts is
generativelanguage.googleapis.com, and it never follows redirects.

Output: the result file always gets fresh content (a placeholder is written before anything
else), holding the model's response, or the error text. One status line is printed, starting
with SUCCESS or FAILED. Exit 0 only on a complete, non-empty answer; 1 on any failure
(truncated, blocked, empty, HTTP error, timeout); 2 on bad usage.
Why not agy: Google's Antigravity FAQ (checked 25 Nov 2026) says wrapping `agy` inside
third-party coding agents such as Claude Code is not supported on consumer plans; it recommends
an AI Studio API key instead (https://antigravity.google/docs/faq.md).
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

API = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
LEVELS = ("low", "medium", "high")
MAX_ATTEMPTS = 3
MIN_TIME_FOR_RETRY = 30


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow redirects: urllib would re-send the key header to the new location."""

    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(_NoRedirect)


def parse_timeout(text: str) -> int:
    m = re.fullmatch(r"(\d+)\s*([ms]?)", text.strip().lower())
    if not m:
        return 540
    n = int(m.group(1))
    return n * 60 if m.group(2) == "m" else n


def split_model(model_id: str):
    base, _, suffix = model_id.rpartition("-")
    if base and suffix in LEVELS:
        return base, suffix
    return model_id, None


_REDACT = ""


def write(path: str, text: str) -> None:
    if _REDACT:
        text = text.replace(_REDACT, "[key]")  # belt and braces: Google never echoes the header
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def fail(result_file: str, status: str, detail: str = "") -> None:
    write(result_file, f"{status}\n{detail}".rstrip() + "\n")
    print(f"FAILED {status}")
    sys.exit(1)


def call(model: str, prompt: str, level, key: str, timeout: float):
    body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}]}
    if level:
        body["generationConfig"] = {"thinkingConfig": {"thinkingLevel": level}}
    req = urllib.request.Request(
        API.format(model=model), data=json.dumps(body).encode("utf-8"), method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with OPENER.open(req, timeout=max(timeout, 1)) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                return resp.status, json.loads(raw), None
            except ValueError:
                return -1, {"error": {"message": "200 response was not JSON: " + raw[:500]}}, None
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(raw)
        except ValueError:
            data = {"error": {"message": raw[:2000]}}
        return e.code, data, e.headers
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return 0, {"error": {"message": f"network error: {type(e).__name__}: {e}"}}, None


def retry_delay(data: dict, headers) -> float:
    """Gemini puts the wait in error.details[].retryDelay (e.g. "34s"); fall back to Retry-After."""
    for d in (data.get("error") or {}).get("details") or []:
        m = re.fullmatch(r"(\d+(?:\.\d+)?)s", str(d.get("retryDelay", "")))
        if m:
            return float(m.group(1))
    ra = headers.get("Retry-After", "") if headers is not None else ""
    return float(ra) if str(ra).isdigit() else 15.0


def error_text(code: int, data: dict) -> str:
    err = data.get("error") if isinstance(data, dict) else None
    msg = (err.get("message") if isinstance(err, dict) else None) or str(data)[:2000]
    hint = {400: "bad request (check the model id)",
            403: "key rejected or API not enabled for this key",
            404: "model id not found",
            429: "rate limit or spend cap reached (check AI Studio)",
            0: "could not reach the API",
            -1: "unreadable response"}.get(code, "API error")
    return f"HTTP {code}: {hint}\n{msg}"


def run(model_id: str, prompt_file: str, result_file: str, total: int) -> None:
    global _REDACT
    deadline = time.monotonic() + total
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    _REDACT = key if len(key) >= 8 else ""
    if not key:
        write(result_file, "NO KEY: GEMINI_API_KEY is not set in this environment.\n")
        print("NO KEY: GEMINI_API_KEY is not set (user env var); open a new terminal after setting it")
        sys.exit(1)
    if not re.fullmatch(r"[\x21-\x7e]+", key):  # printable ASCII, no spaces/control chars
        fail(result_file, "KEY MALFORMED: GEMINI_API_KEY has unexpected characters (value not shown)")
    if not re.fullmatch(r"[\w.\-]+", model_id):
        fail(result_file, f"BAD MODEL ID: {model_id[:80]!r}")
    try:
        with open(prompt_file, "rb") as f:
            prompt = f.read().decode("utf-8-sig")
    except (OSError, UnicodeDecodeError) as e:
        fail(result_file, f"PROMPT UNREADABLE: {type(e).__name__} (save it as UTF-8)", str(e)[:300])
    if "\x00" in prompt:
        fail(result_file, "PROMPT UNREADABLE: contains NUL bytes (UTF-16 file? save it as UTF-8)")

    model, level = split_model(model_id)
    note = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        remaining = deadline - time.monotonic()
        code, data, headers = call(model, prompt, level, key, remaining)
        if code == 200:
            break
        last = attempt == MAX_ATTEMPTS
        if code == 400 and level and "thinking" in json.dumps(data).lower() and not last:
            level, note = None, " (thinking level rejected; retried without it)"
            continue
        if code in (429, 503) and not last:
            wait = min(retry_delay(data, headers), 60.0)
            if deadline - time.monotonic() - wait >= MIN_TIME_FOR_RETRY:
                time.sleep(wait)
                continue
        fail(result_file, error_text(code, data).splitlines()[0] + note, error_text(code, data))

    cands = data.get("candidates") or []
    parts = (cands[0].get("content") or {}).get("parts", []) if cands else []
    text = "".join(p.get("text", "") for p in parts if not p.get("thought"))
    finish = cands[0].get("finishReason", "?") if cands else "NO_CANDIDATES"
    usage = data.get("usageMetadata") or {}
    tokens = (f"input_tokens={usage.get('promptTokenCount')} output_tokens={usage.get('candidatesTokenCount')} "
              f"thinking_tokens={usage.get('thoughtsTokenCount', 0)} chars_sent={len(prompt)}")
    if not text:
        block = (data.get("promptFeedback") or {}).get("blockReason")
        fail(result_file, f"EMPTY RESPONSE finish={finish} blockReason={block} {tokens}{note}")
    if finish == "MAX_TOKENS":
        write(result_file, text + "\n\n[TRUNCATED: MAX_TOKENS]\n")
        print(f"FAILED TRUNCATED finish=MAX_TOKENS model={model} {tokens}{note}")
        sys.exit(1)
    if finish != "STOP":
        write(result_file, text + f"\n\n[INCOMPLETE: finish={finish}]\n")
        print(f"FAILED INCOMPLETE finish={finish} model={model} {tokens}{note}")
        sys.exit(1)
    write(result_file, text)
    print(f"SUCCESS model={model} level={level or 'default'} finish={finish} {tokens}{note}")
    sys.exit(0)


def main():
    if len(sys.argv) < 4:
        print("usage: python -I gemini-api.py <model-id> <prompt-file> <result-file> [9m|300s]")
        sys.exit(2)
    model_id, prompt_file, result_file = sys.argv[1:4]
    total = parse_timeout(sys.argv[4]) if len(sys.argv) > 4 else 540
    # Fresh content first, so a crash or kill never leaves an older answer looking current.
    write(result_file, "(no result: gemini-api.py did not finish)\n")
    try:
        run(model_id, prompt_file, result_file, total)
    except SystemExit:
        raise
    except Exception as e:  # never print locals or the request; type + short message only
        fail(result_file, f"SCRIPT ERROR {type(e).__name__}", str(e)[:300])


if __name__ == "__main__":
    main()
