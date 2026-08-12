#!/usr/bin/env bash
# Behavior tests for bin/fm-board.sh path resolution and absent-board soft sync.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-board)
BOARD_HOME="$TMP_ROOT/home"
mkdir -p "$BOARD_HOME/data"

# Fake crewboard host that records argv for pass-through assertions.
FAKE_BIN="$TMP_ROOT/fake-crewboard.js"
cat > "$FAKE_BIN" <<'EOF'
#!/usr/bin/env node
const fs = require('node:fs');
const out = process.env.FM_BOARD_FAKE_LOG;
if (out) fs.writeFileSync(out, JSON.stringify(process.argv.slice(1)) + '\n');
if (process.argv.includes('--fail')) {
  process.stderr.write('fake-crewboard: forced failure\n');
  process.exit(1);
}
process.stdout.write('fake-crewboard: ok\n');
EOF
chmod +x "$FAKE_BIN"

capture() {
  local file=$1
  shift
  "$@" >"$file" 2>&1
}

test_help_lists_ownership() {
  local out
  out="$TMP_ROOT/help.out"
  capture "$out" "$ROOT/bin/fm-board.sh" --help \
    || fail "fm-board.sh --help exited non-zero"
  assert_grep "FM_CREWBOARD_BIN" "$out" "help must document FM_CREWBOARD_BIN"
  assert_grep "crewboard-fleet" "$out" "help must document the fleet board path"
  assert_grep "sync" "$out" "help must document the sync verb"
  pass "fm-board.sh: --help documents ownership and paths"
}

test_absent_host_errors_on_passthrough() {
  local out status
  out="$TMP_ROOT/absent-host.out"
  set +e
  FM_HOME="$BOARD_HOME" \
  FM_CREWBOARD_BIN="$TMP_ROOT/missing-crewboard.js" \
  FM_CREWBOARD_BOARD="$BOARD_HOME/data/crewboard-fleet" \
    capture "$out" "$ROOT/bin/fm-board.sh" list
  status=$?
  set -e
  expect_code 1 "$status" "passthrough must fail when host binary is missing"
  assert_grep "host binary missing" "$out" "must name the missing host binary"
  assert_grep "missing-crewboard.js" "$out" "must include the concrete host path"
  pass "fm-board.sh: missing host binary fails loudly on pass-through"
}

test_absent_board_errors_on_passthrough() {
  local out status
  out="$TMP_ROOT/absent-board.out"
  set +e
  FM_HOME="$BOARD_HOME" \
  FM_CREWBOARD_BIN="$FAKE_BIN" \
  FM_CREWBOARD_BOARD="$BOARD_HOME/data/no-such-board" \
    capture "$out" "$ROOT/bin/fm-board.sh" list
  status=$?
  set -e
  expect_code 1 "$status" "passthrough must fail when fleet board is missing"
  assert_grep "fleet board missing" "$out" "must name the missing fleet board"
  assert_grep "no-such-board" "$out" "must include the concrete board path"
  pass "fm-board.sh: missing fleet board fails loudly on pass-through"
}

test_sync_skips_when_board_absent() {
  local out status
  out="$TMP_ROOT/sync-absent-board.out"
  set +e
  FM_HOME="$BOARD_HOME" \
  FM_CREWBOARD_BIN="$FAKE_BIN" \
  FM_CREWBOARD_BOARD="$BOARD_HOME/data/absent-board" \
    capture "$out" "$ROOT/bin/fm-board.sh" sync
  status=$?
  set -e
  expect_code 0 "$status" "sync must exit 0 when the board is absent"
  assert_grep "sync skipped" "$out" "sync must emit a single non-fatal skip notice"
  assert_grep "absent-board" "$out" "skip notice must name the missing board"
  pass "fm-board.sh: sync soft-skips when the fleet board is absent"
}

test_sync_skips_when_host_absent() {
  local out status
  out="$TMP_ROOT/sync-absent-host.out"
  set +e
  FM_HOME="$BOARD_HOME" \
  FM_CREWBOARD_BIN="$TMP_ROOT/no-host.js" \
  FM_CREWBOARD_BOARD="$BOARD_HOME/data/crewboard-fleet" \
    capture "$out" "$ROOT/bin/fm-board.sh" sync
  status=$?
  set -e
  expect_code 0 "$status" "sync must exit 0 when the host binary is absent"
  assert_grep "sync skipped" "$out" "sync must emit a non-fatal skip notice"
  assert_grep "no-host.js" "$out" "skip notice must name the missing host"
  pass "fm-board.sh: sync soft-skips when the host binary is absent"
}

test_passthrough_injects_board_path() {
  local board log out status
  board="$BOARD_HOME/data/crewboard-fleet"
  mkdir -p "$board/.crewboard"
  log="$TMP_ROOT/fake-argv.json"
  out="$TMP_ROOT/passthrough.out"
  rm -f "$log"
  set +e
  FM_HOME="$BOARD_HOME" \
  FM_CREWBOARD_BIN="$FAKE_BIN" \
  FM_CREWBOARD_BOARD="$board" \
  FM_BOARD_FAKE_LOG="$log" \
    capture "$out" "$ROOT/bin/fm-board.sh" list --json
  status=$?
  set -e
  expect_code 0 "$status" "passthrough with present host+board must succeed (got: $(cat "$out"))"
  assert_present "$log" "fake host did not record argv"
  assert_grep '"list"' "$log" "must pass the list subcommand through"
  assert_grep '"--board"' "$log" "must inject --board"
  assert_grep "$board" "$log" "must inject the resolved fleet board path"
  pass "fm-board.sh: pass-through injects the fleet board path"
}

test_sync_imports_when_board_present() {
  local board log backlog out status
  board="$BOARD_HOME/data/crewboard-fleet"
  mkdir -p "$board/.crewboard"
  backlog="$BOARD_HOME/data/backlog.md"
  printf '%s\n' '## Queued' '- [ ] sample-task-a1 - sample title' > "$backlog"
  log="$TMP_ROOT/fake-sync-argv.json"
  out="$TMP_ROOT/sync-present.out"
  rm -f "$log"
  set +e
  FM_HOME="$BOARD_HOME" \
  FM_CREWBOARD_BIN="$FAKE_BIN" \
  FM_CREWBOARD_BOARD="$board" \
  FM_BOARD_FAKE_LOG="$log" \
    capture "$out" "$ROOT/bin/fm-board.sh" sync
  status=$?
  set -e
  expect_code 0 "$status" "sync with present board must succeed (got: $(cat "$out"))"
  assert_present "$log" "fake host did not record sync argv"
  assert_grep '"import"' "$log" "sync must call import"
  assert_grep '"tasks-axi"' "$log" "sync must import tasks-axi"
  assert_grep "$backlog" "$log" "sync must pass the backlog path"
  assert_grep '"board-keeper"' "$log" "sync must act as board-keeper"
  pass "fm-board.sh: sync re-imports the tasks-axi backlog when the board exists"
}

test_help_lists_ownership
test_absent_host_errors_on_passthrough
test_absent_board_errors_on_passthrough
test_sync_skips_when_board_absent
test_sync_skips_when_host_absent
test_passthrough_injects_board_path
test_sync_imports_when_board_present
