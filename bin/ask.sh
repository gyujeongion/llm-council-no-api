#!/usr/bin/env bash
#
# ask.sh — query one external model CLI non-interactively and print clean text.
#
# Part of claude-code-council. This is the "panel" caller: Claude (the chairman)
# shells out to ONE locally-installed, already-authenticated model CLI and gets
# a plain-text second opinion back. No API keys. No browser automation. No token
# scraping. It only runs official CLIs you have already logged into.
#
# Usage:
#   ask.sh <provider> "<prompt>"
#
# Providers (built-in):
#   gemini   -> Google gemini-cli        (gemini -p "...")
#   gpt      -> OpenAI codex CLI          (codex exec ...)
#
# Binary discovery (in order):
#   1. Explicit override env var:  COUNCIL_GEMINI_BIN / COUNCIL_GPT_BIN
#   2. `which <default-bin>` on PATH
#
# Defaults can be overridden so this works on any machine:
#   COUNCIL_GEMINI_BIN   default: gemini
#   COUNCIL_GPT_BIN      default: codex
#   COUNCIL_GEMINI_MODEL optional: passed to gemini --model
#   COUNCIL_GPT_MODEL    optional: passed to codex -m
#   COUNCIL_GPT_TIMEOUT  optional seconds (default 180), needs coreutils `timeout`/`gtimeout`
#
# Exit codes:
#   0  success (response on stdout)
#   2  provider unknown
#   3  provider binary not found / not on PATH
#   4  provider call failed (not logged in, quota, network, etc.)

set -uo pipefail

PROVIDER="${1:-}"
PROMPT="${2:-}"

die() { echo "council:ask: $*" >&2; }

if [[ -z "$PROVIDER" || -z "$PROMPT" ]]; then
  die "usage: ask.sh <gemini|gpt> \"<prompt>\""
  exit 2
fi

# Resolve a binary: prefer explicit override, else look on PATH.
resolve_bin() {
  local override="$1" default="$2"
  if [[ -n "$override" ]]; then
    if command -v "$override" >/dev/null 2>&1; then command -v "$override"; return 0; fi
    if [[ -x "$override" ]]; then echo "$override"; return 0; fi
    return 1
  fi
  command -v "$default" 2>/dev/null
}

# Optional timeout wrapper (graceful if coreutils not installed).
timeout_cmd() {
  local secs="$1"; shift
  if command -v timeout  >/dev/null 2>&1; then timeout  "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  "$@"  # no timeout available; run as-is
}

case "$PROVIDER" in
  gemini)
    BIN="$(resolve_bin "${COUNCIL_GEMINI_BIN:-}" gemini)" || { die "gemini CLI not found. Install gemini-cli and run 'gemini' once to log in, or set COUNCIL_GEMINI_BIN."; exit 3; }
    ARGS=(-p "$PROMPT")
    [[ -n "${COUNCIL_GEMINI_MODEL:-}" ]] && ARGS=(--model "$COUNCIL_GEMINI_MODEL" "${ARGS[@]}")
    OUT="$("$BIN" "${ARGS[@]}" 2>/dev/null)"; rc=$?
    if [[ $rc -ne 0 || -z "$OUT" ]]; then
      die "gemini call failed (rc=$rc). Are you logged in? Try running '$BIN' interactively once."
      exit 4
    fi
    printf '%s\n' "$OUT"
    ;;

  gpt)
    BIN="$(resolve_bin "${COUNCIL_GPT_BIN:-}" codex)" || { die "codex CLI not found. Install OpenAI codex CLI and run 'codex login', or set COUNCIL_GPT_BIN."; exit 3; }
    TO="${COUNCIL_GPT_TIMEOUT:-180}"
    TMPF="$(mktemp "${TMPDIR:-/tmp}/council_gpt.XXXXXX")"
    # Run codex from an empty, isolated working directory. codex is an agentic CLI
    # that can read files in its cwd to reason about them; pointing it at an empty
    # dir guarantees it sees ONLY the prompt text we pass — it cannot reach your
    # repo or working tree. The privacy boundary is enforced here, not just promised.
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/council_gptwd.XXXXXX")"
    trap 'rm -f "$TMPF"; rm -rf "$WORKDIR"' EXIT
    ARGS=(exec --skip-git-repo-check -s read-only -o "$TMPF")
    [[ -n "${COUNCIL_GPT_MODEL:-}" ]] && ARGS+=(-m "$COUNCIL_GPT_MODEL")
    ARGS+=("$PROMPT")
    ( cd "$WORKDIR" && timeout_cmd "$TO" "$BIN" "${ARGS[@]}" ) >/dev/null 2>&1
    rc=$?
    OUT="$(cat "$TMPF" 2>/dev/null)"
    if [[ $rc -ne 0 || -z "$OUT" ]]; then
      die "codex call failed (rc=$rc). Are you logged in? Try 'codex login'."
      exit 4
    fi
    printf '%s\n' "$OUT"
    ;;

  *)
    die "unknown provider '$PROVIDER' (expected: gemini | gpt)"
    exit 2
    ;;
esac
