#!/usr/bin/env bash
# Behavior tests for the provisional Mistral Vibe crew harness.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-vibe-harness)

make_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
state=$(cat "$FM_FAKE_VIBE_STATE" 2>/dev/null || true)
case "$*" in
  *'#{pane_current_path}'*) printf '%s\n' "$FM_FAKE_PANE_PATH"; exit 0 ;;
  *'#{pane_id}'*) printf '%s\n' '%42'; exit 0 ;;
  *'#{cursor_y}'*) printf '%s\n' 1; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf '%s\n' firstmate; exit 0 ;;
  list-windows|has-session|new-session|new-window|kill-window) exit 0 ;;
  send-keys)
    literal= previous=
    for arg in "$@"; do
      if [ "$previous" = -l ]; then literal=$arg; break; fi
      previous=$arg
    done
    if [ -n "$literal" ]; then
      printf '%s\n' "$literal" >> "$FM_FAKE_VIBE_LAUNCH_LOG"
      case "$literal" in
        *'vibe --trust --auto-approve'*)
          printf '%s\n' "${FM_FAKE_VIBE_DIALOG:-trust}" > "$FM_FAKE_VIBE_STATE"
          ;;
      esac
    elif [ "$state" = trust ] && printf ' %s ' "$*" | grep -Fq ' Enter '; then
      printf '%s\n' ready > "$FM_FAKE_VIBE_STATE"
      printf '%s\n' Enter >> "$FM_FAKE_VIBE_KEY_LOG"
    fi
    exit 0
    ;;
  capture-pane)
    case "$state" in
      trust)
        printf '%s\n' 'Trust this folder?' '› Trust folder     Don'\''t trust'
        ;;
      update)
        printf '%s\n' 'A new Vibe release is available'
        ;;
      ready)
        printf '%s\n' 'Mistral Vibe v2.24.0' \
          '────────────────────────────────────────────────────────────────────── default ─' \
          '>' \
          '────────────────────────────────────────────────────────────────────────────────'
        ;;
      *) printf '%s\n' '$ '; ;;
    esac
    exit 0
    ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse gh-axi gh vibe
  printf '%s\n' "$fakebin"
}

make_case() {  # <name> <id>
  local name=$1 id=$2 case_dir home proj wt fakebin
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(make_fakebin "$case_dir")
  mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config"
  printf 'brief for Vibe\n' > "$home/data/$id/brief.md"
  printf '%s\n' vibe > "$home/config/crew-harness"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  touch "$home/state/.last-watcher-beat"
  : > "$case_dir/launch.log"
  : > "$case_dir/key.log"
  : > "$case_dir/vibe.state"
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin"
}

run_spawn() {  # <case-dir> <home> <project> <worktree> <fakebin> <id> [args...]
  local case_dir=$1 home=$2 proj=$3 wt=$4 fakebin=$5 id=$6
  shift 6
  FM_ROOT_OVERRIDE='' FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_DATA_OVERRIDE="$home/data" FM_PROJECTS_OVERRIDE="$home/projects" \
    FM_CONFIG_OVERRIDE="$home/config" FM_SPAWN_NO_GUARD=1 \
    FM_FAKE_PANE_PATH="$wt" FM_FAKE_VIBE_STATE="$case_dir/vibe.state" \
    FM_FAKE_VIBE_LAUNCH_LOG="$case_dir/launch.log" \
    FM_FAKE_VIBE_KEY_LOG="$case_dir/key.log" TMUX='fake,1,0' \
    FM_VIBE_READY_POLLS=3 FM_VIBE_POLL_INTERVAL=0 PATH="$fakebin:$PATH" \
    "$SPAWN" "$id" "$proj" --harness vibe --scout "$@" 2>&1
}

read_case() {
  IFS='|' read -r CASE_DIR HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR <<EOF
$1
EOF
}

test_vibe_launch_accepts_trust_dialog_without_model_or_effort_flags() {
  local id=voice-vibe-z1 rec out launch meta
  rec=$(make_case launch "$id")
  read_case "$rec"
  out=$(run_spawn "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id" \
    --model an-observed-model --effort xhigh)
  expect_code 0 $? "Vibe scout spawn should accept its verified trust dialog: $out"
  assert_contains "$out" "spawned $id harness=vibe kind=scout" "Vibe spawn did not report success"

  launch=$(cat "$CASE_DIR/launch.log")
  assert_contains "$launch" 'VIBE_ENABLE_UPDATE_CHECKS=false vibe --trust --auto-approve' \
    "Vibe launch did not use its verified update, trust, and autonomy flags"
  assert_not_contains "$launch" '--model' "Vibe launch emitted unsupported --model"
  assert_not_contains "$launch" '--effort' "Vibe launch emitted unsupported --effort"
  [ "$(cat "$CASE_DIR/key.log")" = Enter ] \
    || fail "Vibe trust dialog was not accepted exactly once"
  meta="$HOME_DIR/state/$id.meta"
  assert_grep 'model=an-observed-model' "$meta" "Vibe metadata lost the requested model axis"
  assert_grep 'effort=xhigh' "$meta" "Vibe metadata lost the requested effort axis"
  pass "fm-spawn: Vibe launches autonomously, accepts its known trust dialog, and omits unsupported profile flags"
}

test_vibe_update_dialog_refuses_without_pressing_enter() {
  local id=voice-vibe-update-z1 rec out rc
  rec=$(make_case update "$id")
  read_case "$rec"
  out=$(FM_FAKE_VIBE_DIALOG=update run_spawn \
    "$CASE_DIR" "$HOME_DIR" "$PROJ_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$id")
  rc=$?
  [ "$rc" -ne 0 ] || fail "Vibe update dialog must make spawn fail closed"
  assert_contains "$out" 'vibe showed an update dialog' "Vibe update dialog was not diagnosed"
  [ ! -s "$CASE_DIR/key.log" ] || fail "Vibe update dialog received a trust-dialog Enter"
  pass "fm-spawn: Vibe update dialog fails closed without a blind Enter"
}

test_vibe_busy_tail_is_harness_scoped() {
  local busy idle other
  busy=$(fm_busy_classify tmux fake:window vibe test "$TMP_ROOT" \
    'Generating… (22s Esc/Ctrl+C to interrupt')
  idle=$(fm_busy_classify tmux fake:window vibe test "$TMP_ROOT" 'Mistral Vibe v2.24.0')
  other=$(fm_busy_classify tmux fake:window codex test "$TMP_ROOT" \
    'Generating… (22s Esc/Ctrl+C to interrupt')
  [ "$busy" = 'busy vibe-regex' ] || fail "Vibe busy tail misclassified as '$busy'"
  [ "$idle" = 'idle vibe-regex' ] || fail "Vibe idle tail misclassified as '$idle'"
  [ "$other" = 'unknown codex-unverified' ] \
    || fail "Vibe busy tail leaked into another harness: '$other'"
  pass "fm-busy-lib: Vibe's provisional busy tail is scoped to Vibe only"
}

test_vibe_launch_accepts_trust_dialog_without_model_or_effort_flags
test_vibe_update_dialog_refuses_without_pressing_enter
test_vibe_busy_tail_is_harness_scoped
