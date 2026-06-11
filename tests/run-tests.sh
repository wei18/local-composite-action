#!/usr/bin/env bash
# Test harness: extracts the real bash from action.yml and runs it
# against simulated GitHub runner directory layouts.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_YML="$SCRIPT_DIR/../action.yml"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
WORK="$TMP_DIR/sandbox"
STEP_FIND="$TMP_DIR/step_find.sh"
STEP_LINK="$TMP_DIR/step_link.sh"
PASS=0; FAIL=0

# Extract step scripts from action.yml (steps: 0=check, 1=find, 2=link)
ruby -ryaml -e '
a = YAML.load_file(ARGV[0])
steps = a["runs"]["steps"]
File.write(ARGV[1], steps[1]["run"])
File.write(ARGV[2], steps[2]["run"])
' "$ACTION_YML" "$STEP_FIND" "$STEP_LINK" || { echo "extraction failed"; exit 1; }

run_find() { # env: ACTION_PATH ACTION_REPOSITORY GITHUB_OUTPUT
  bash "$STEP_FIND"
}
run_link() { # env: ACTION_REPOSITORY_PATH ACTION_REPOSITORY GITHUB_WORKSPACE
  bash "$STEP_LINK"
}

assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ✅ $1"
  else FAIL=$((FAIL+1)); echo "  ❌ $1"; echo "     expected: $2"; echo "     actual:   $3"; fi
}
assert_ok()   { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ✅ $1"; else FAIL=$((FAIL+1)); echo "  ❌ $1 (exit=$2)"; fi; }
assert_fail() { if [ "$2" -ne 0 ]; then PASS=$((PASS+1)); echo "  ✅ $1"; else FAIL=$((FAIL+1)); echo "  ❌ $1 (expected nonzero exit)"; fi; }

fresh() { rm -rf "$WORK"; mkdir -p "$WORK"; }
out_of() { grep '^path=' "$1" | head -1 | cut -d= -f2-; }

echo "=== T1: same-repo walk-up (default happy path, must keep working) ==="
fresh
SELF="$WORK/work/_actions/wei18/local-composite-action/main"
mkdir -p "$SELF/.github/composite-actions/example"
export GITHUB_OUTPUT="$WORK/out1"; : > "$GITHUB_OUTPUT"
ACTION_PATH="$SELF/.github/composite-actions/example" ACTION_REPOSITORY="wei18/local-composite-action" run_find >/dev/null 2>&1
assert_ok "step exits 0" $?
assert_eq "outputs checkout root" "$SELF" "$(out_of "$GITHUB_OUTPUT")"

echo "=== T2: mixed-case uses: (e.g. end user wrote Wei18/...) ==="
fresh
REAL="$WORK/work/_actions/Wei18/local-composite-action/main"
mkdir -p "$REAL/.github/composite-actions/example"
export GITHUB_OUTPUT="$WORK/out2"; : > "$GITHUB_OUTPUT"
ACTION_PATH="$REAL/.github/composite-actions/example" ACTION_REPOSITORY="Wei18/local-composite-action" run_find >/dev/null 2>&1
assert_ok "step exits 0" $?
assert_eq "output path keeps real on-disk casing" "$REAL" "$(out_of "$GITHUB_OUTPUT")"

echo "=== T3: third-party caller relying on default action_path ==="
# Without action_path, github.action_path points at THIS action's own checkout,
# so the caller's repo must be found via the _actions directory fallback.
fresh
mkdir -p "$WORK/work/_actions/wei18/local-composite-action/v1"
CALLER="$WORK/work/_actions/acme/tools/v2"
mkdir -p "$CALLER/.github/actions/foo"
export GITHUB_OUTPUT="$WORK/out3"; : > "$GITHUB_OUTPUT"
ACTION_PATH="$WORK/work/_actions/wei18/local-composite-action/v1" ACTION_REPOSITORY="acme/tools" run_find >/dev/null 2>&1
assert_ok "step exits 0 (finds caller repo via _actions)" $?
assert_eq "outputs caller checkout root" "$CALLER" "$(out_of "$GITHUB_OUTPUT")"

echo "=== T4: relative/degenerate action_path must not hang ==="
fresh
export GITHUB_OUTPUT="$WORK/out4"; : > "$GITHUB_OUTPUT"
perl -e 'alarm 5; $rc = system(@ARGV); exit($rc == -1 || ($rc & 127) ? 124 : $rc >> 8)' \
  /usr/bin/env ACTION_PATH="." ACTION_REPOSITORY="acme/tools" GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$STEP_FIND" >/dev/null 2>&1
rc=$?
if [ "$rc" -ge 124 ]; then FAIL=$((FAIL+1)); echo "  ❌ infinite loop (killed by 5s alarm, exit=$rc)"; else PASS=$((PASS+1)); echo "  ✅ terminates quickly (exit=$rc)"; fi

echo "=== T5: empty action_repository gives clear error ==="
fresh
export GITHUB_OUTPUT="$WORK/out5"; : > "$GITHUB_OUTPUT"
msg=$(ACTION_PATH="$WORK/work/_actions/wei18/local-composite-action/v1" ACTION_REPOSITORY="" run_find 2>&1); rc=$?
assert_fail "step exits nonzero" $rc
case "$msg" in *empty*|*required*) PASS=$((PASS+1)); echo "  ✅ error message says input is empty/required";;
  *) FAIL=$((FAIL+1)); echo "  ❌ unhelpful error: $msg";; esac

echo "=== T6: create symlink twice (two composite actions in one job) ==="
fresh
TARGET="$WORK/work/_actions/acme/tools/v2"; mkdir -p "$TARGET"
GWS="$WORK/work/consumer/consumer"; mkdir -p "$GWS"
ACTION_REPOSITORY_PATH="$TARGET" ACTION_REPOSITORY="acme/tools" GITHUB_WORKSPACE="$GWS" run_link >/dev/null 2>&1
assert_ok "first run exits 0" $?
ACTION_REPOSITORY_PATH="$TARGET" ACTION_REPOSITORY="acme/tools" GITHUB_WORKSPACE="$GWS" run_link >/dev/null 2>&1
assert_ok "second run exits 0" $?
LINK="$WORK/work/consumer/acme/tools"
assert_eq "symlink resolves to checkout" "$(cd "$TARGET" && pwd -P)" "$(cd "$LINK" 2>/dev/null && pwd -P)"
if [ -e "$TARGET/v2" ]; then FAIL=$((FAIL+1)); echo "  ❌ garbage nested symlink created inside checkout: $TARGET/v2 -> $(readlink "$TARGET/v2")"
else PASS=$((PASS+1)); echo "  ✅ no nested garbage symlink inside checkout"; fi

echo "=== T7: mixed-case action_repository still serves lowercase ./../ refs ==="
fresh
TARGET="$WORK/work/_actions/Acme/Tools/v2"; mkdir -p "$TARGET"
GWS="$WORK/work/consumer/consumer"; mkdir -p "$GWS"
ACTION_REPOSITORY_PATH="$TARGET" ACTION_REPOSITORY="Acme/Tools" GITHUB_WORKSPACE="$GWS" run_link >/dev/null 2>&1
assert_ok "run exits 0" $?
assert_eq "as-given path resolves" "$(cd "$TARGET" && pwd -P)" "$(cd "$WORK/work/consumer/Acme/Tools" 2>/dev/null && pwd -P)"
assert_eq "lowercase path resolves"  "$(cd "$TARGET" && pwd -P)" "$(cd "$WORK/work/consumer/acme/tools" 2>/dev/null && pwd -P)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
