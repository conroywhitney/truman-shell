#!/bin/bash
#
# TrumanShell Sandbox Hook — Shell Wrapper
#
# Resolves the truman-shell binary path and delegates to the TypeScript handler.
# Prefers the escript (dist/truman-shell) for fast startup; falls back to bin/truman-shell.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRUMAN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Prefer escript (fast) over bin wrapper (mix startup)
if [ -x "$TRUMAN_ROOT/dist/truman-shell" ]; then
  export TRUMAN_SHELL_PATH="$TRUMAN_ROOT/dist/truman-shell"
else
  export TRUMAN_SHELL_PATH="$TRUMAN_ROOT/bin/truman-shell"
fi

cat | npx tsx "$SCRIPT_DIR/truman-sandbox.ts"
