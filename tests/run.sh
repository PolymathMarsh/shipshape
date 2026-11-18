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
expect 1 connstr    "Server=db;Database=x;User Id=sa;Pass""word=p4ssw0rd;\n"   # split: no literal fixture in the repo
expect 0 empty      ''
expect 1 two-on-line  "AIza$(printf 'A%.0s' {1..35}) client_secret=\"abcdefgh\"
"
expect 1 aws-secret   "AWS_SECRET_""ACCESS_KEY=$(printf 'x%.0s' {1..40})
"
expect 1 url-creds    "DATABASE_URL=postgres://app"":s3cretpw@db.internal/app
"
expect 1 pgp          "-----BEGIN PGP PRIV""ATE KEY BLOCK-----
"
expect 0 url-no-creds "see https://example.com/docs and git@github.com:o/r.git
"
# output must never contain the matched secret
printf 'k = "sk-%s"
' "$k" > "$t/leak"; out=$(bash "$scan" "$t/leak" 2>&1)
case "$out" in *"$k"*) echo "FAIL leak (secret printed)"; fail=1;; *) echo "ok   no-leak";; esac
rm -f "$t/missing"; bash "$scan" "$t/missing" >/dev/null 2>&1; if [ $? -eq 2 ]; then echo "ok   missing-file"; else echo "FAIL missing-file"; fail=1; fi

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
check multi-mixed    1 "d1': possible github-token" "$t/c1'" -- "$t/c1" "$t/d1"            # R1
check multi-clean    0 "clean (2 files)"            -       -- "$t/c1" "$t/c2"            # R2
check multi-summary  1 "in 1 of 3 files"            -       -- "$t/c1" "$t/d1" "$t/c2"    # R3
check no-args        2 -                            -       --                            # R4
check missing-in-set 2 -                            "possible" -- "$t/d1" "$t/missing"    # R4: fails before scanning
check multi-no-leak  1 -                            "$k"    -- "$t/c1" "$t/d1"            # R5
check spaces         0 "clean (1 files)"            -       -- "$t/my file.txt"           # edge: spaces
check duplicate      1 "in 2 of 2 files"            -       -- "$t/d1" "$t/d1"            # edge: counted twice

# ---- round-2 fixes (triage of review findings) ----
printf 'key = "sk-%s"\n' "$k" > "$t/d2"
both=$(bash "$scan" "$t/d1" "$t/d2" 2>&1); got=$?                                         # R1: both dirty names, full format
case "$got:$both" in "1:"*"d1': possible github-token on line(s): 1"*"d2': possible api-key-sk on line(s): 1"*) echo "ok   multi-two-dirty";; *) echo "FAIL multi-two-dirty (exit $got): $both"; fail=1;; esac
so=$(bash "$scan" "$t/c1" "$t/c2" 2>/dev/null); got=$?                                  # R2: summary on stdout
case "$got:$so" in "0:scan-secrets: clean (2 files)") echo "ok   clean-on-stdout";; *) echo "FAIL clean-on-stdout (exit $got): $so"; fail=1;; esac
se=$(bash "$scan" "$t/c1" "$t/d1" 2>&1 >/dev/null); got=$?                              # R3: full summary on stderr
case "$got:$se" in "1:scan-secrets: POSSIBLE SECRETS FOUND in 1 of 2 files - do not send.") echo "ok   summary-on-stderr";; *) echo "FAIL summary-on-stderr (exit $got): $se"; fail=1;; esac
check usage-message  2 "usage:"                     -       --                            # R4: message printed
check dir-arg        2 "not a readable file"        -       -- "$t"                       # R4: directory refused
# fail closed when grep itself errors mid-scan: a fake grep on PATH that exits 2
mkdir -p "$t/bin"; printf '#!/usr/bin/env bash\nexit 2\n' > "$t/bin/grep"; chmod +x "$t/bin/grep"
ge=$(PATH="$t/bin:$PATH" bash "$scan" "$t/c1" 2>&1); got=$?
case "$got:$ge" in "2:"*"could not scan"*"grep failed (exit 2)"*) echo "ok   grep-error-fails-closed";; *) echo "FAIL grep-error-fails-closed (exit $got): $ge"; fail=1;; esac
# file names with control characters are printed without them (skipped where such names can't be created)
nl_name="$t/$(printf 'bad\nscan-secrets: clean')"
if printf 'token: ghp_%s\n' "$k" > "$nl_name" 2>/dev/null; then
  out=$(bash "$scan" "$nl_name" 2>/dev/null); got=$?
  case "$got:$out" in "1:"*"
scan-secrets: clean"*) echo "FAIL control-chars-in-name"; fail=1;;
    "1:"*"possible github-token"*) echo "ok   control-chars-in-name";;
    *) echo "FAIL control-chars-in-name (exit $got)"; fail=1;; esac
else echo "skip control-chars-in-name (platform can't create the name)"; fi

# ---- 0.2.1 fixes (redline review) ----
printf 'token: ghp_%s\n' "$k" > "$t/my dirty.txt"
check spaces-dirty   1 "my dirty.txt': possible"    -       -- "$t/my dirty.txt"          # R1 + spaces
check missing-with-clean 2 "not a readable file"    "scan-secrets: clean" -- "$t/c1" "$t/missing"       # R4, exact spec case
: > "$t/e1"; : > "$t/e2"
check multi-empty    0 "clean (2 files)"            -       -- "$t/e1" "$t/e2"            # edge: empty files
# binary file (NUL byte) with a secret: still flagged, line numbers stay numbers
printf 'bin\000ary\ntoken: ghp_%s\n' "$k" > "$t/bin1"
bo=$(bash "$scan" "$t/bin1" 2>/dev/null); got=$?
case "$got:$bo" in "1:"*"on line(s): 2 "*) echo "ok   binary-file";; *) echo "FAIL binary-file (exit $got): $bo"; fail=1;; esac
# with shell tracing on, the matched secret must not appear anywhere
xo=$(bash -x "$scan" "$t/d1" 2>&1); got=$?
case "$got:$xo" in *"$k"*) echo "FAIL xtrace-no-leak (secret in trace)"; fail=1;;
  "1:"*"possible github-token"*) echo "ok   xtrace-no-leak";; *) echo "FAIL xtrace-no-leak (exit $got)"; fail=1;; esac

# ---- 0.2.2 fixes (second redline review) ----
# a failure later in the pipe (cut/tr) must fail closed too: fake cut on PATH that exits 1
mkdir -p "$t/bin2"; printf '#!/usr/bin/env bash\nexit 1\n' > "$t/bin2/cut"; chmod +x "$t/bin2/cut"
po=$(PATH="$t/bin2:$PATH" bash "$scan" "$t/d1" 2>&1); got=$?
case "$got:$po" in "2:"*"could not scan"*"cut/tr failed"*) echo "ok   pipe-error-fails-closed";; *) echo "FAIL pipe-error-fails-closed (exit $got): $po"; fail=1;; esac
# Turkish locale must not break case-insensitive matching (skipped if the locale isn't installed)
printf 'API_KEY = "%s"\n' "$k" > "$t/tr1"
if locale -a 2>/dev/null | grep -qi '^tr_TR'; then
  trl=$(locale -a | grep -i '^tr_TR' | head -1)
  LC_ALL="$trl" bash "$scan" "$t/tr1" >/dev/null 2>&1; got=$?
  if [ "$got" -eq 1 ]; then echo "ok   turkish-locale"; else echo "FAIL turkish-locale (exit $got)"; fail=1; fi
else echo "skip turkish-locale (tr_TR locale not installed)"; fi
# with bash's xpg_echo on, a literal backslash-n in a file name must not start a new line (skipped where unsupported)
bs_name="$t/"'bad\nscan-secrets: clean'
if { printf 'token: ghp_%s\n' "$k" > "$bs_name"; } 2>/dev/null; then
  xe=$(bash -O xpg_echo "$scan" "$bs_name" 2>/dev/null); got=$?
  case "$got:$xe" in *"
scan-secrets: clean"*) echo "FAIL xpg-echo-name"; fail=1;; "1:"*"possible github-token"*) echo "ok   xpg-echo-name";; *) echo "FAIL xpg-echo-name (exit $got)"; fail=1;; esac
else echo "skip xpg-echo-name (platform can't create the name)"; fi
# the repo's own test file and scanner must pass the gate (no literal fixtures left)
# every file in the repo: tracked and untracked-but-not-ignored via git when available, else
# everything outside .git. NUL-separated so odd names survive; deleted-but-tracked files are skipped.
root="$here/.."
files=()
if git -C "$root" rev-parse >/dev/null 2>&1; then
  while IFS= read -r -d '' x; do [ -f "$root/$x" ] && files+=("$root/$x"); done \
    < <(git -C "$root" ls-files -z --cached --others --exclude-standard)
else
  while IFS= read -r -d '' x; do files+=("$x"); done < <(find "$root" -type f -not -path '*/.git/*' -print0)
fi
check repo-self-clean 0 "scan-secrets: clean (${#files[@]} files)" - -- "${files[@]}"

# ---- 0.2.4 fixes (fourth redline review) ----
# a grep error is reported as a grep error even when cut also fails
gc=$(PATH="$t/bin:$t/bin2:$PATH" bash "$scan" "$t/c1" 2>&1); got=$?
case "$got:$gc" in "2:"*"grep failed (exit 2)"*) echo "ok   grep-error-wins";; *) echo "FAIL grep-error-wins (exit $got): $gc"; fail=1;; esac
# a scan error mid-run prints no findings from earlier files, only the error
real_grep=$(command -v grep)
mkdir -p "$t/bin3"; printf '#!/usr/bin/env bash
case "${@: -1}" in *boom*) exit 2;; esac
exec "%s" "$@"
' "$real_grep" > "$t/bin3/grep"; chmod +x "$t/bin3/grep"
printf 'x
' > "$t/boom"
so=$(PATH="$t/bin3:$PATH" bash "$scan" "$t/d1" "$t/boom" 2>/dev/null); got=$?
if [ "$got" -eq 2 ] && [ -z "$so" ]; then echo "ok   no-partial-output"; else echo "FAIL no-partial-output (exit $got): $so"; fail=1; fi
# unreadable file (skipped where chmod can't remove read access: Windows, root)
printf 'x\n' > "$t/noread"; chmod 000 "$t/noread" 2>/dev/null
if [ -r "$t/noread" ]; then echo "skip unreadable-file (platform ignores chmod)"
else check unreadable-file 2 "not a readable file" - -- "$t/noread"; fi
# ---- 0.2.5: file names are quoted, so a name can't pass for part of a finding ----
spoof="$t/x: possible api-key-sk on line(s): 9"
if printf 'token: ghp_%s\n' "$k" > "$spoof" 2>/dev/null; then
  so=$(bash "$scan" "$spoof" 2>/dev/null); got=$?
  want="'$spoof': possible github-token on line(s): 1 "
  if [ "$got" -eq 1 ] && [ "$so" = "$want" ]; then echo "ok   quoted-name-spoof"; else echo "FAIL quoted-name-spoof (exit $got): $so"; fail=1; fi
else echo "skip quoted-name-spoof (platform can't create the name)"; fi
q="$t/it's.txt"; printf 'token: ghp_%s\n' "$k" > "$q"
so=$(bash "$scan" "$q" 2>/dev/null); got=$?
want="'$t/it'\\''s.txt': possible github-token on line(s): 1 "
if [ "$got" -eq 1 ] && [ "$so" = "$want" ]; then echo "ok   quote-in-name-escaped"; else echo "FAIL quote-in-name-escaped (exit $got): $so"; fail=1; fi
exit $fail
