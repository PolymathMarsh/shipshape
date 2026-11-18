#!/usr/bin/env bash
# scan-secrets.sh <file> [file...]
# Blocks review prompts that look like they contain secrets.
# Prints only file names, line numbers and the kind of match, never the matched text.
# Exit 0 = all clean, 1 = possible secret found,
#      2 = usage error (nothing scanned) or scan error (stopped; do not send).
# Portable: bash + POSIX tools (tr, cut) + grep -E/-a (GNU or BSD).
{ set +x; } 2>/dev/null   # never trace: traces could show matched text
set -u
export LC_ALL=C           # byte-wise, locale-independent matching (e.g. Turkish i/I case folding)
say() { printf '%s\n' "$*"; }   # printf, not echo: no backslash interpretation in file names
[ "$#" -gt 0 ] || { say "usage: scan-secrets.sh <file> [file...]" >&2; exit 2; }
# Display form of a file name: control characters (newlines etc.) removed so a name can't fake a line.
show() { printf '%s' "$1" | tr -d '\000-\037\177'; }
# Fail closed: check every argument before scanning any of them.
for f in "$@"; do
  { [ -f "$f" ] && [ -r "$f" ]; } || { say "scan-secrets: not a readable file: $(show "$f")" >&2; exit 2; }
done

# name|pattern   (all matched case-insensitively)
rules='
api-key-sk|sk-[A-Za-z0-9_-]{20,}
aws-access-key-id|(AKIA|ASIA)[0-9A-Z]{16}
aws-secret-key|aws_?secret_?access_?key["'"'"' ]*[:=]
google-api-key|AIza[0-9A-Za-z_-]{35}
github-token|gh[pousr]_[A-Za-z0-9]{30,}
github-pat|github_pat_[A-Za-z0-9_]{30,}
slack-token|xox[abprs]-[A-Za-z0-9-]{10,}
stripe-live-key|(sk|rk)_live_[A-Za-z0-9]{16,}
jwt|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
private-key|-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----
url-credentials|[a-z][a-z0-9+.-]*://[^/ :@"'"'"']+:[^/ @"'"'"']+@
connection-string|(password|pwd)=[^;"'"'"' ]{4,}
assignment|(password|passwd|secret|api_?key|apikey|access_?token|auth_?token|client_?secret)["'"'"' ]*[:=][ ]*["'"'"'][^"'"'"']{6,}["'"'"']
'

total=0 dirty=0
for f in "$@"; do
  total=$((total + 1))
  hit=0
  while IFS='|' read -r name pat; do
    [ -z "$name" ] && continue
    # Matched text goes straight from grep to cut; only line numbers are kept.
    # -a reads binary files as text, so they are scanned and line numbers stay numbers.
    # The subshell exits with grep's status, or 9 if cut or tr failed.
    lines=$(grep -naEi -- "$pat" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' '
            p=("${PIPESTATUS[@]}")
            { [ "${p[1]}" -eq 0 ] && [ "${p[2]}" -eq 0 ]; } || exit 9
            exit "${p[0]}")
    rc=$?
    # 0 = match, 1 = no match, anything else = error. Fail closed on errors.
    if [ "$rc" -gt 1 ]; then
      say "scan-secrets: could not scan $(show "$f") (exit $rc) - do not send." >&2
      exit 2
    fi
    if [ "$rc" -eq 0 ]; then
      hit=1
      say "$(show "$f"): possible $name on line(s): $lines"
    fi
  done <<EOF
$rules
EOF
  [ "$hit" -eq 1 ] && dirty=$((dirty + 1))
done

if [ "$dirty" -gt 0 ]; then
  say "scan-secrets: POSSIBLE SECRETS FOUND in $dirty of $total files - do not send." >&2
  exit 1
fi
say "scan-secrets: clean ($total files)"
exit 0
