#!/usr/bin/env bash
# Shared config for the stack token benchmark. Source me.
# Empirical facts confirmed via smoke test 2026-06-03:
#   -p json usage fields: input_tokens/output_tokens/cache_creation_input_tokens/cache_read_input_tokens
#   cache_creation split: ephemeral_1h_input_tokens / ephemeral_5m_input_tokens (CC uses 1h cache)
#   headroom stdout has a banner before JSON -> strip with: sed -n '/^{/,$p'
#   real ~/.claude already effortLevel=high -> stack arm needs no override
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="$BENCH_DIR/results"
KOFFEE="$HOME/dev/KoffeeMud"
CLAUDE_BIN="/home/zrom/.local/bin/claude"
OPUS_MODEL_ENV='claude-opus-4-8[1m]'   # match the stack's ANTHROPIC_DEFAULT_OPUS_MODEL

# Opus rate card, USD per 1M tokens. CONFIRM against current Anthropic pricing.
RATE_INPUT=15.00
RATE_OUTPUT=75.00
RATE_CACHE_WRITE_5M=18.75   # 1.25x input
RATE_CACHE_WRITE_1H=30.00   # 2x input
RATE_CACHE_READ=1.50        # 0.1x input

# Isolated virgin config dir (auth-only + minimal settings, effort high).
build_virgin_dir() {
  local vd="$1"
  mkdir -p "$vd"
  cp "$HOME/.claude/.credentials.json" "$vd"/ 2>/dev/null || {
    echo "FATAL: no ~/.claude/.credentials.json to seed virgin auth" >&2; return 1; }
  printf '%s\n' '{"model":"claude-opus-4-8","effortLevel":"high"}' > "$vd/settings.json"
}

mkdir -p "$RESULTS"
