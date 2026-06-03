#!/usr/bin/env bash
# setup-vanilla-profile.sh — build/refresh ~/.claude-vanilla, a "pre-repo + caveman + Opus"
# Claude Code profile used by the bashrc `claude` function (vanilla), while the real ~/.claude
# stays the full token-optimization stack (used by `claude-cbm`).
#
# Idempotent. Touches ONLY ~/.claude-vanilla/. Never edits ~/.claude or ~/.claude.json.
#
# What it strips vs the live stack: hooks, user MCP (CBM/headroom/serena), the cct global
# CLAUDE.md rules, the stack env vars, and the context-mode plugin. What it keeps: caveman +
# the four non-repo plugins (context7, superpowers, fullstack-dev-skills, claude-code-setup),
# your OAuth login, and Opus 4.8.
set -euo pipefail

SRC="$HOME/.claude"
SRC_JSON="$HOME/.claude.json"
VDIR="$HOME/.claude-vanilla"

command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 1; }
[ -d "$SRC/plugins" ] || { echo "FATAL: $SRC/plugins missing — is the stack installed?" >&2; exit 1; }
[ -f "$SRC/.credentials.json" ] || { echo "FATAL: $SRC/.credentials.json missing (no auth to share)" >&2; exit 1; }
[ -f "$SRC/settings.json" ] || { echo "FATAL: $SRC/settings.json missing" >&2; exit 1; }

mkdir -p "$VDIR"

# 1) Share the heavy/stable assets by symlink (plugin registry+cache, OAuth token).
ln -sfn "$SRC/plugins"          "$VDIR/plugins"
ln -sf  "$SRC/.credentials.json" "$VDIR/.credentials.json"

# 2) claude.json: copy live account/UI state (keeps onboarding done + oauthAccount), but with
#    NO user MCP servers (drops CBM/headroom/serena). Written into the profile dir.
if [ -f "$SRC_JSON" ]; then
  jq '.mcpServers = {}' "$SRC_JSON" > "$VDIR/.claude.json"
else
  printf '%s\n' '{"hasCompletedOnboarding":true,"mcpServers":{}}' > "$VDIR/.claude.json"
fi

# 3) Curated settings.json derived from the live one:
#    - model opus 4.8, effort high (your choice)
#    - enabledPlugins minus context-mode (repo-added); caveman + the 4 non-repo plugins kept
#    - extraKnownMarketplaces minus context-mode
#    - env reduced to the pre-repo MAX_THINKING_TOKENS only
#    - NO hooks, NO statusLine
jq '{
  model: "claude-opus-4-8",
  effortLevel: "high",
  enabledPlugins: ((.enabledPlugins // {}) | del(."context-mode@context-mode")),
  extraKnownMarketplaces: ((.extraKnownMarketplaces // {}) | del(."context-mode")),
  env: ((.env // {}) | {MAX_THINKING_TOKENS} | with_entries(select(.value != null)))
}' "$SRC/settings.json" > "$VDIR/settings.json"

# 4) NO global CLAUDE.md in the profile (drops the cct forced-CBM rules).
rm -f "$VDIR/CLAUDE.md" 2>/dev/null || true

echo "✓ vanilla profile built at $VDIR"
echo "  plugins      → $(readlink "$VDIR/plugins")"
echo "  credentials  → $(readlink "$VDIR/.credentials.json")"
echo "  enabledPlugins: $(jq -rc '.enabledPlugins|keys' "$VDIR/settings.json")"
echo "  user mcpServers: $(jq -rc '.mcpServers|keys' "$VDIR/.claude.json")"
echo "  hooks: $(jq -rc '.hooks // "none"' "$VDIR/settings.json")  |  global CLAUDE.md: $([ -f "$VDIR/CLAUDE.md" ] && echo present || echo none)"
echo
echo "Launch vanilla via the bashrc 'claude' function, full stack via 'claude-cbm'."
