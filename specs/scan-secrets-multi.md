# Spec: scan-secrets-multi

## Objective
`scan-secrets.sh` accepts one or more files, scans them all, and ends with one summary line. It still never prints a matched value.

## Requirements
- **R1 Multiple files.** `scan-secrets.sh a b c` scans every file. Each finding line names its file in single quotes: `'<file>': possible <kind> on line(s): …`, with any `'` in the name written as `'\''`. *(Quoting added 18 Nov 2026 with the owner's approval, so a crafted file name can't pass for part of a finding. The original format was `<file>: possible …`.)*
  **Check:** test: one clean and one dirty file → exit 1, and the output names the dirty file but not the clean one.
- **R2 Clean summary.** If every file is clean → exit 0 with stdout `scan-secrets: clean (N files)`.
  **Check:** test: 2 clean files → exit 0, and the output contains `clean (2 files)`.
- **R3 Hit summary.** If any file has a finding → exit 1 with stderr `scan-secrets: POSSIBLE SECRETS FOUND in K of N files - do not send.`
  **Check:** test: 1 dirty of 3 → the output contains `in 1 of 3 files`.
- **R4 Fail closed.** No arguments, or any argument that isn't a readable file → exit 2 with a usage/error message, **before** anything is scanned.
  **Check:** tests: no args → exit 2; one clean file plus one missing path → exit 2.
- **R5 No leaks.** Matched text is never printed, with single or multiple files.
  **Check:** the existing no-leak test, plus a two-file version.
- **R6 Backward compatible.** The single-file exit codes don't change, and all 15 existing tests pass with identical inputs and expectations. Fixture strings may be split in the source so the repo holds no literal fake secrets. *(Wording changed 18 Nov 2026 with the owner's approval; the original said "unchanged". The 4 fixtures split in 0.2.2 (connstr, aws-secret, url-creds, pgp) were shown to be byte-identical by SHA-256. The 5th split fixture, privkey, was split earlier, in commit 84a6c5a, before this feature began.)*
  **Check:** `bash tests/run.sh` shows the original 15 `ok` lines, plus the new tests.
- **R7 Portable.** Bash plus POSIX tools (`tr`, `cut`) and `grep -E`/`-a` (both GNU and BSD grep): no sed, no other GNU-only flags. *(Wording changed 18 Nov 2026 with the owner's approval; the original "bash + grep -E only" was stricter than intended.)*
  **Check:** `grep -nE '\bsed\b|grep -P' scan-secrets.sh` → no hits. The Linux/macOS/Windows CI run after merge is outside the loop, so locally this is UNVERIFIED and gets confirmed after the push.

## Edge cases
- File names with spaces: test with `"my file.txt"`.
- The same file listed twice: count it twice, don't de-duplicate.
- Empty files count as clean.

## Out of scope
Scanning directories or recursing into them, new secret patterns, any change to SKILL.md.

## Definition of done
All the checks above pass locally and in CI, both reviews are triaged, the work is merged to `main` and pushed, and the report is shown. *(Changed 18 Nov 2026 with the owner's approval; the original said "committed on the local branch `shipshape/scan-secrets-multi` (not pushed)", which was right for the first round only.)*
