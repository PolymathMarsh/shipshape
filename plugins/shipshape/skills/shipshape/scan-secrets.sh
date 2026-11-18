#!/usr/bin/env bash
# scan-secrets.sh <file>
# Blocks a review prompt that looks like it contains secrets.
# Prints only line numbers and the kind of match, never the matched text.
# Exit 0 = clean, 1 = possible secret found, 2 = usage error.
# Portable: bash + grep -E (GNU or BSD). No sed.
set -u
f="${1:-}"
{ [ -n "$f" ] && [ -f "$f" ]; } || { echo "usage: scan-secrets.sh <file>" >&2; exit 2; }

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

hits=0
while IFS='|' read -r name pat; do
  [ -z "$name" ] && continue
  lines=$(grep -nEi -- "$pat" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' ') || true
  if [ -n "$lines" ]; then
    hits=1
    echo "possible $name on line(s): $lines"
  fi
done <<EOF
$rules
EOF

if [ "$hits" -eq 1 ]; then
  echo "scan-secrets: POSSIBLE SECRETS FOUND in $f - do not send." >&2
  exit 1
fi
echo "scan-secrets: clean"
exit 0
