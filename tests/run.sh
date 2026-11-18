#!/usr/bin/env bash
# Tests for scan-secrets.sh. Dirty fixtures are generated at runtime so no fake secret is committed.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
scan="$here/../plugins/shipshape/skills/shipshape/scan-secrets.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
fail=0
expect() { # expect <want-exit> <name> <content>
  printf '%b' "$3" > "$t/$2"
  bash "$scan" "$t/$2" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$1" ]; then echo "ok   $2"; else echo "FAIL $2 (want $1, got $got)"; fail=1; fi
}
k="abcdefghijklmnopqrstuvwxyz0123456789"
expect 0 clean      'const total = add(1, 2);\nfunction add(a, b) { return a + b }\n'
expect 0 prose      'The password field must be at least 8 characters.\n'
expect 1 openai     "const key = \"sk-$k\";\n"
expect 1 aws        "id = AKIA$(printf 'ABCDEFGHIJKLMNOP')\n"
expect 1 github     "token: ghp_$k\n"
expect 1 privkey    "-----BEGIN RSA PRIV""ATE KEY-----\nMIIE\n"   # split so the repo holds no literal key header
expect 1 assignment "password = \"hunter2hunter2\"\n"
expect 1 connstr    "Server=db;Database=x;User Id=sa;Password=p4ssw0rd;\n"
expect 0 empty      ''
expect 1 two-on-line  "AIza$(printf 'A%.0s' {1..35}) client_secret=\"abcdefgh\"
"
expect 1 aws-secret   "AWS_SECRET_ACCESS_KEY=$(printf 'x%.0s' {1..40})
"
expect 1 url-creds    "DATABASE_URL=postgres://app:s3cretpw@db.internal/app
"
expect 1 pgp          "-----BEGIN PGP PRIVATE KEY BLOCK-----
"
expect 0 url-no-creds "see https://example.com/docs and git@github.com:o/r.git
"
# output must never contain the matched secret
printf 'k = "sk-%s"
' "$k" > "$t/leak"; out=$(bash "$scan" "$t/leak" 2>&1)
case "$out" in *"$k"*) echo "FAIL leak (secret printed)"; fail=1;; *) echo "ok   no-leak";; esac
rm -f "$t/missing"; bash "$scan" "$t/missing" >/dev/null 2>&1; [ $? -eq 2 ] || { echo "FAIL missing-file"; fail=1; }
exit $fail
