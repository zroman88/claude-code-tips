# Spec: Token benchmark — virgin Opus 4.8 vs CBM/ctx/serena/headroom stack

**Date:** 2026-06-03
**Status:** Approved (design), pending implementation plan
**Author:** Roman Zilikovich (with Claude)

## Problem

The user observed that running Claude Code through this repo's stack (CBM + context-mode +
serena + headroom + caveman, enforced by hooks and a forced-CBM-first global `CLAUDE.md`)
did **not** produce the token savings the stack's narrative promises — same token usage, and
on a per-dollar enterprise account, *higher* cost than virgin Claude Code.

This benchmark tests that observation rigorously on a large real Java codebase
(`~/dev/KoffeeMud`, already CBM-indexed), measuring token usage and answer quality for the
same question asked of both configurations.

## Goal & non-goals

**Goal:** Produce a reproducible, decomposed token + quality comparison between virgin Opus
4.8 and the full stack, on a worst-case and a best-case task, so the verdict explains *why*
the numbers differ — not just *that* they differ.

**Non-goals:** Publication-grade statistics; tuning the stack; measuring multi-turn
long-session context preservation (a real but separate claim, out of scope here).

## Key facts established during design

- `claude` is a bashrc shell function: `claude() { command headroom wrap claude -- "$@"; }`.
  Headroom is an **API-layer proxy** between the CLI and Anthropic, not an MCP tool.
- CBM, context-mode, serena, caveman, context7 are MCP servers + plugins loaded via
  `~/.claude/settings.json`. They inject tool schemas into the **system prompt every turn** —
  a fixed per-turn token tax independent of the work done.
- Stack settings: `model: claude-opus-4-8`, env `ANTHROPIC_DEFAULT_OPUS_MODEL:
  claude-opus-4-8[1m]`, `CLAUDE_CODE_SUBAGENT_MODEL: claude-sonnet-4-6`.
- The user runs this benchmark on a **Max subscription** (no per-request dollar figure). The
  earlier "higher cost in dollars" observation came from a separate **enterprise** account.
  → Primary metric must be **raw token counts**; dollars are derived synthetically.

## Design

### 1. The two arms (only the stack varies)

| | Arm A — virgin | Arm B — stack |
|---|---|---|
| Invocation | `CLAUDE_CONFIG_DIR=$VIRGIN command claude -p …` | `headroom wrap claude -- -p …` |
| Config | mktemp dir, minimal `settings.json` = `{"model":"claude-opus-4-8","effortLevel":"high"}`, **no MCP, no hooks, no plugins, no global CLAUDE.md** | real `~/.claude` (CBM, context-mode, serena, caveman, context7, hooks, global CLAUDE.md) |
| Discovery | free Read/Grep/Glob | forced CBM-first (gate hook), context-mode sandbox, headroom API compression |

Constants across both arms:
- cwd = `~/dev/KoffeeMud`
- model = `claude-opus-4-8`, **`effortLevel: high`** (matched — passed to Arm B too, overriding
  the stack's default `xhigh`, so thinking depth is not a confound)
- identical question string per task
- `--output-format json`

What is intentionally part of Arm B only (because it *is* "the version the user runs"): the
pre-built CBM index of KoffeeMud, and the global `CLAUDE.md` routing rules. Their one-time
build cost is amortized and noted, not charged per run.

### 2. Tasks (one worst-case, one best-case)

- **Task A — ticker (stack worst-case):** *"How is the MUD ticker implemented?"* Single
  focused lookup; no large raw output to amortize the fixed MCP schema tax. A stack loss here
  means "loses on small queries," not "worthless."
- **Task B — command dispatch (stack best-case):** *"How does CoffeeMud parse and dispatch a
  player's typed command end-to-end, from input string to executed Command?"* Multi-hop trace
  across many large Java files; the naive path forces virgin CC to grep→read many big files —
  the exact scenario context-mode/CBM target.

Two tasks (not three) to bound quota.

### 3. Metric

- **Primary:** raw token counts per run from `-p json` `usage`: `input_tokens`,
  `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`. Plan-independent.
- **Derived:** synthetic USD = token counts × published Opus 4.8 rate card (same rates both
  arms), reproducing the enterprise-dollar view without a dollar plan.
- Field names in `-p json` to be confirmed in the smoke test before the sweep.

### 4. Token decomposition

One **baseline run per arm** with a trivial prompt (`"Reply with OK"`) isolates the **fixed
tax** (system prompt + tool schemas) from **work tokens** (task total − baseline). This is the
number most likely to explain "same tokens, higher cost": Arm B pays tens of thousands of
schema tokens before any work.

### 5. Quality grading (blind, rubric-based)

1. Establish ground truth for both tasks independently via CBM (before reading either arm's
   answer).
2. Write a fact rubric per task (e.g. ticker: `Tickable`/`TickableGroup`/`ServiceEngine`
   thread, tick interval constant, registration path, the tick loop).
3. Grade both answers **blind** (arm labels stripped) on fact coverage + hallucination count.
   Caveman terseness is not penalized — graded on technical facts only.

### 6. Harness & run count

- Bash driver loops runs, writes each `-p json` to a results dir.
- Zero-dep aggregator (Node ESM or python3) computes median + spread, decomposition, synthetic
  $, emits a markdown report.
- Location: `bench/` in this repo (not shipped by `install.sh`, which copies only specific
  dirs).
- **Runs:** 2 baseline (1×2 arms) + Task A 6 (3×2) + Task B 6 (3×2) = **14 runs**.
- Opus high on a big repo is slow → smoke-test 1 run/arm first (catch breakage cheaply), then
  run the full sweep in the background under a Monitor.

### 7. Caveats surfaced in the report

- **Headroom side-channel:** headroom may issue its own compression model calls invisible to
  claude's `-p` usage → could undercount Arm B. Check for a `headroom stats`/meter and
  reconcile one run; flag if unmeasurable. This is the most likely path by which the user saw
  "higher" while a naive token count shows "lower."
- One-time CBM index build cost is amortized, not per-run.
- N=3 is directional, not publication-grade.
- `claude -p` is invoked as a subprocess from within an interactive Claude session; runs are
  independent processes with their own sessions.

## Success criteria

- 14 runs complete with parseable `-p json` for each.
- Report shows, per arm per task: median total tokens (4-way split), synthetic $, fixed-tax vs
  work-token decomposition, and blind quality score.
- A written verdict that either confirms or refutes the user's observation, with the
  decomposition explaining the mechanism.

## Open items for the implementation plan

- Confirm `-p json` field names (`usage`, `total_cost_usd`, `result`, `num_turns`,
  `duration_ms`) in the smoke test.
- Confirm headroom passes `--output-format json` through cleanly.
- Pick aggregator language (Node ESM matches repo `bin/` convention).
- Decide whether `bench/` is committed or gitignored.
