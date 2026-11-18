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

# ---- multiple files (spec: specs/scan-secrets-multi.md) ----
check() { # check <name> <want-exit> <must-contain|-> <must-not-contain|-> -- files...
  name=$1 want=$2 has=$3 hasnt=$4; shift 5
  out=$(bash "$scan" "$@" 2>&1); got=$?
  ok=1
  [ "$got" -eq "$want" ] || ok=0
  [ "$has" = "-" ] || case "$out" in *"$has"*) ;; *) ok=0;; esac
  [ "$hasnt" = "-" ] || case "$out" in *"$hasnt"*) ok=0;; esac
  if [ "$ok" -eq 1 ]; then echo "ok   $name"; else echo "FAIL $name (exit $got): $out"; fail=1; fi
}
printf 'nothing here\n' > "$t/c1"; printf 'still nothing\n' > "$t/c2"; printf 'also clean\n' > "$t/c3"
printf 'token: ghp_%s\n' "$k" > "$t/d1"
printf 'nothing here\n' > "$t/my file.txt"
check multi-mixed    1 "d1: possible github-token" "c1:" -- "$t/c1" "$t/d1"            # R1
check multi-clean    0 "clean (2 files)"            -       -- "$t/c1" "$t/c2"            # R2
check multi-summary  1 "in 1 of 3 files"            -       -- "$t/c1" "$t/d1" "$t/c2"    # R3
check no-args        2 -                            -       --                            # R4
check missing-in-set 2 -                            "possible" -- "$t/d1" "$t/missing"    # R4: fails before scanning
check multi-no-leak  1 -                            "$k"    -- "$t/c1" "$t/d1"            # R5
check spaces         0 "clean (1 files)"            -       -- "$t/my file.txt"           # edge: spaces
check duplicate      1 "in 2 of 2 files"            -       -- "$t/d1" "$t/d1"            # edge: counted twice
exit $fail
