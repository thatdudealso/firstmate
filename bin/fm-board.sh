#!/usr/bin/env bash
# Thin wrapper that exposes the local Crewboard host CLI against this home's
# fleet board.
#
# Ownership: this script is the single firstmate entry for crew-board access.
# The host binary and board path live outside the tracked repo (captain-private);
# AGENTS.md section 7 owns the always-on coordination contract; this header owns
# path resolution and the optional backlog sync verb.
#
# Paths (override with env for tests or alternate installs):
#   FM_CREWBOARD_BIN   host CLI (default: $HOME/.crewboard-host/bin/crewboard.js)
#   FM_CREWBOARD_BOARD fleet board directory (default: $FM_HOME/data/crewboard-fleet)
#   Backlog for sync:  $FM_HOME/data/backlog.md (or FM_DATA_OVERRIDE/backlog.md)
#
# Usage:
#   fm-board.sh sync
#     Re-import data/backlog.md into the fleet board as board-keeper when the
#     host binary and board both exist. Board absence is never a hard fleet
#     dependency: prints one non-fatal notice and exits 0. When the board is
#     present, import failures are reported and exit non-zero.
#   fm-board.sh <crewboard-args...>
#     Pass through to the host CLI with --board set to the fleet board (unless
#     the caller already passed --board). Missing host binary or board fails
#     loudly naming the concrete missing piece - never a silent no-op.
#
# Ticket identity for tasks-axi imports: source.key is id:<task-id>. Workers
# comment and move that ticket; they do not create duplicates.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

die() {
  printf 'fm-board: %s\n' "$*" >&2
  exit 1
}

notice() {
  printf 'fm-board: %s\n' "$*" >&2
}

resolve_bin() {
  local bin=${FM_CREWBOARD_BIN:-$HOME/.crewboard-host/bin/crewboard.js}
  printf '%s\n' "$bin"
}

resolve_board() {
  local board=${FM_CREWBOARD_BOARD:-$DATA/crewboard-fleet}
  printf '%s\n' "$board"
}

require_bin() {
  local bin=$1
  [ -n "$bin" ] || die "host binary path is empty (set FM_CREWBOARD_BIN)"
  [ -e "$bin" ] || die "host binary missing: $bin (expected ~/.crewboard-host/bin/crewboard.js or FM_CREWBOARD_BIN)"
  [ -x "$bin" ] || die "host binary not executable: $bin"
}

require_board() {
  local board=$1
  [ -n "$board" ] || die "fleet board path is empty (set FM_CREWBOARD_BOARD)"
  [ -d "$board" ] || die "fleet board missing: $board (expected \$FM_HOME/data/crewboard-fleet)"
  [ -d "$board/.crewboard" ] || die "fleet board is not initialized (no .crewboard under $board)"
}

args_have_board_flag() {
  local a
  for a in "$@"; do
    case "$a" in
      --board|--board=*) return 0 ;;
    esac
  done
  return 1
}

run_crewboard() {
  local bin=$1
  shift
  if command -v node >/dev/null 2>&1 && [[ "$bin" == *.js ]]; then
    node "$bin" "$@"
  else
    "$bin" "$@"
  fi
}

sync_backlog() {
  local bin board backlog
  bin=$(resolve_bin)
  board=$(resolve_board)
  backlog="$DATA/backlog.md"

  if [ ! -e "$bin" ]; then
    notice "sync skipped: host binary missing ($bin); fleet continues without the crew board"
    return 0
  fi
  if [ ! -x "$bin" ]; then
    notice "sync skipped: host binary not executable ($bin); fleet continues without the crew board"
    return 0
  fi
  if [ ! -d "$board" ] || [ ! -d "$board/.crewboard" ]; then
    notice "sync skipped: fleet board absent or uninitialized ($board); fleet continues without the crew board"
    return 0
  fi
  if [ ! -f "$backlog" ]; then
    notice "sync skipped: backlog missing ($backlog); fleet continues without the crew board"
    return 0
  fi

  run_crewboard "$bin" import tasks-axi "$backlog" --board "$board" --as board-keeper
}

[ "$#" -ge 1 ] || { usage >&2; exit 2; }

if [ "$1" = sync ]; then
  [ "$#" -eq 1 ] || die "sync takes no extra arguments"
  sync_backlog
  exit $?
fi

BIN=$(resolve_bin)
BOARD=$(resolve_board)
require_bin "$BIN"

PASS_ARGS=("$@")
if ! args_have_board_flag "${PASS_ARGS[@]}"; then
  require_board "$BOARD"
  PASS_ARGS+=(--board "$BOARD")
fi

run_crewboard "$BIN" "${PASS_ARGS[@]}"
