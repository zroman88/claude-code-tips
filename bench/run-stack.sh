#!/usr/bin/env bash
# Usage: run-stack.sh "<question>" "<output-tag>"
# Real ~/.claude already effortLevel=high; no override needed.
source "$(dirname "$0")/lib/common.sh"
Q="$1"; TAG="$2"

cd "$KOFFEE" || exit 1
headroom wrap claude -- -p "$Q" \
  --dangerously-skip-permissions \
  --output-format json \
  2> "$RESULTS/$TAG.err" \
| sed -n '/^{/,$p' > "$RESULTS/$TAG.json"   # strip headroom banner before JSON
echo "stack done: $TAG ($(jq -r '.num_turns // "?"' "$RESULTS/$TAG.json" 2>/dev/null) turns)"
