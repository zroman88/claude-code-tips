#!/usr/bin/env bash
# Usage: run-virgin.sh "<question>" "<output-tag>"
source "$(dirname "$0")/lib/common.sh"
Q="$1"; TAG="$2"
VD="/tmp/bench-virgin-cfg"
build_virgin_dir "$VD" || exit 1

cd "$KOFFEE" || exit 1
ANTHROPIC_DEFAULT_OPUS_MODEL="$OPUS_MODEL_ENV" \
CLAUDE_CONFIG_DIR="$VD" \
command "$CLAUDE_BIN" -p "$Q" \
  --strict-mcp-config \
  --dangerously-skip-permissions \
  --output-format json \
  > "$RESULTS/$TAG.json" 2> "$RESULTS/$TAG.err"
echo "virgin done: $TAG ($(jq -r '.num_turns // "?"' "$RESULTS/$TAG.json" 2>/dev/null) turns)"
