#!/usr/bin/env bash
# Export one branch of the repository as a plain directory (no git metadata) and anonymize it.
# Works on macOS and Linux (uses perl for in-place edits, no GNU-only tools).
#
# Usage:  bash make_anon_artifact.sh [output-dir]
# Env:    REPO_URL (default: the GitHub repo), BRANCH (default: claude/dpruntime-legacy-java-compat),
#         NAME (default: oca) — new tool name used instead of daikonplusplus / Daikon++
# Produces <output-dir>/ and <output-dir>.zip.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/erfan-arvan/daikonplusplus.git}"
BRANCH="${BRANCH:-claude/dpruntime-legacy-java-compat}"
OUT="${1:-oca-artifact}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
NEWPKG="anonymous"   # replaces the Java package prefix edu.njit.jerse
NAME="${NAME:-oca}"  # replaces the tool name daikonplusplus / daikonpp (and Daikon++ -> Oca)
NAME_TITLE="$(printf '%s' "${NAME:0:1}" | tr '[:lower:]' '[:upper:]')${NAME:1}"
NAME_UPPER="$(printf '%s' "$NAME" | tr '[:lower:]' '[:upper:]')"

for tool in git tar perl zip grep; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool"; exit 1; }
done
[[ -e "$OUT" ]] && { echo "$OUT already exists; remove it or pick another name"; exit 1; }

# 1) Download only that branch and export its files without any git metadata.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --quiet --branch "$BRANCH" --single-branch --depth 1 "$REPO_URL" "$tmp/repo"
mkdir -p "$OUT"
git -C "$tmp/repo" archive --format=tar HEAD | tar -x -C "$OUT"
cd "$OUT"
rm -f .gitignore .gitattributes .coderabbit.yaml   # git / GitHub-bot config

# Apply a perl substitution to every text file containing the literal text (no-op when none).
replace_all() {
  local needle="$1" expr="$2"
  { grep -rlIF -e "$needle" . || true; } | while IFS= read -r f; do perl -pi -e "$expr" "$f"; done
}

# 2) Java package edu.njit.jerse.daikonplusplus -> anonymous.daikonplusplus
for s in main test; do
  mkdir -p "src/$s/java/$NEWPKG"
  mv "src/$s/java/edu/njit/jerse/daikonplusplus" "src/$s/java/$NEWPKG/"
  rm -rf "src/$s/java/edu"
done
replace_all 'edu.njit.jerse' "s/edu\\.njit\\.jerse/$NEWPKG/g"
replace_all 'edu/njit/jerse' "s#edu/njit/jerse#$NEWPKG#g"

# 3) Author names, personal paths, commit hashes
perl -pi -e 's/Copyright \(c\) 2025 Erfan Arvan/Copyright (c) 2025 Anonymous Authors/' LICENSE
replace_all '/Users/erfanarvan' 's#/Users/erfanarvan#/home/anonymous#g'
perl -pi -e 's/"git_commit":"[^"]*"/"git_commit":"anonymous"/' testdata/daikonpp_runs/baseline/manifest.json
perl -ni -e 'print unless /^Picked up JAVA_TOOL_OPTIONS/' testdata/daikonpp_runs/baseline/daikonpp-run.log
replace_all 'fixes /scratch vs /mmfs1' 's#fixes /scratch vs /mmfs1#resolves symlinked mount points#'

# 4) Tool name: daikonplusplus / daikonpp / DAIKONPP / Daikon++  ->  oca / oca / OCA / Oca
#    (prompts never contain the tool name, so recorded LLM responses still replay)
for s in main test; do
  mv "src/$s/java/$NEWPKG/daikonplusplus" "src/$s/java/$NEWPKG/$NAME"
done
find . -depth -name '*daikonpp*' | while IFS= read -r p; do
  mv "$p" "$(dirname "$p")/$(basename "$p" | sed "s/daikonpp/$NAME/g")"
done
replace_all 'daikonplusplus' "s/daikonplusplus/$NAME/g"
replace_all 'Daikon++'       "s/Daikon\\+\\+/$NAME_TITLE/g"
replace_all 'daikonpp'       "s/daikonpp/$NAME/g"
replace_all 'DAIKONPP'       "s/DAIKONPP/$NAME_UPPER/g"

# 5) Report anything that still looks identifying (review these by hand)
echo "== Remaining matches (should be empty):"
grep -rnIiE 'njit|jerse|erfan|arvan|ea442|mjk76|/mmfs1|anthropic|claude|daikonpp|daikonplusplus|daikon\+\+' . || echo "(none)"
find . -iname '*daikon*' | grep . && echo "(file names above still contain 'daikon')" || true

cd ..
zip -qr "$(basename "$OUT").zip" "$(basename "$OUT")"
echo "== Done: $OUT  and  $OUT.zip"
