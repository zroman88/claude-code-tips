# Stack Token Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure whether the CBM/context-mode/serena/headroom/caveman stack actually saves tokens vs virgin Opus 4.8, on the same questions against `~/dev/KoffeeMud`, with a decomposition that explains the result.

**Architecture:** A bash driver runs `claude -p --output-format json` N times per arm per task. Arm A (virgin) = isolated `CLAUDE_CONFIG_DIR` with auth-only + minimal settings, `--strict-mcp-config`. Arm B (stack) = real `~/.claude` via `headroom wrap`. A zero-dep Node ESM aggregator parses the per-run JSON, computes medians/spread, a fixed-tax-vs-work decomposition, and synthetic USD from a published Opus rate card. Quality is graded blind against a CBM-derived fact rubric.

**Tech Stack:** bash (POSIX), Node ESM (zero-dep, matches repo `bin/` convention), `jq`, `claude` CLI 2.1.161, `headroom` proxy, CBM MCP for ground truth.

**Spec:** `docs/superpowers/specs/2026-06-03-stack-token-benchmark-design.md`

---

## Resolved design decisions

- **Aggregator language:** Node ESM (matches `bin/*.mjs`, zero-dep).
- **`bench/` dir:** committed to the repo (not shipped — `install.sh` copies only specific dirs).
- **Effort parity:** both arms forced to `effortLevel: high`. Virgin gets it via its config-dir `settings.json`; stack-arm override mechanism is confirmed in Task 1 (Step: effort override).
- **Model parity:** neither arm passes `--model`; both export `ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-8[1m]'` and set `model: claude-opus-4-8` in settings, so both resolve to the identical model.
- **Permissions:** both arms pass `--dangerously-skip-permissions` (read-only benchmark; equal footing, no headless permission stalls).
- **Run order:** strictly sequential (headroom proxy binds `127.0.0.1:8787`; parallel runs would collide and skew load).

## File structure

| Path | Responsibility |
|---|---|
| `bench/README.md` | What this is, how to run, how to read results |
| `bench/lib/common.sh` | Shared: paths, the Opus rate card, virgin-dir builder, one `run_arm` function |
| `bench/run-virgin.sh` | Single virgin run → writes `<results>/<tag>.json` + `.err` |
| `bench/run-stack.sh` | Single stack run → writes `<results>/<tag>.json` + `.err` |
| `bench/drive.sh` | Loops baseline + Task A + Task B, N=3, sequential; emits a manifest |
| `bench/aggregate.mjs` | Parses run JSON → `bench/results/summary.json` + `bench/results/report.md` |
| `bench/rubrics/ticker.md` | Fact rubric for Task A (authored from CBM ground truth) |
| `bench/rubrics/dispatch.md` | Fact rubric for Task B (authored from CBM ground truth) |
| `bench/grade.mjs` | Blind quality grading scaffold → `bench/results/quality.json` |
| `bench/results/` | Per-run JSON, manifest, summary, report (gitignored except `.gitkeep`) |

---

## Task 0: Scaffold `bench/`

**Files:**
- Create: `bench/README.md`
- Create: `bench/results/.gitkeep`
- Create: `bench/.gitignore`

- [ ] **Step 1: Create the directory skeleton and gitignore**

`bench/.gitignore`:
```gitignore
# Per-run artifacts are noise; keep the dir, ignore contents except the report.
results/*
!results/.gitkeep
!results/report.md
!results/summary.json
```

- [ ] **Step 2: Write `bench/README.md`**

```markdown
# Stack token benchmark

Compares virgin Opus 4.8 vs the full CBM/ctx/serena/headroom/caveman stack on
identical questions against ~/dev/KoffeeMud. See
`docs/superpowers/specs/2026-06-03-stack-token-benchmark-design.md`.

## Run
    bash bench/drive.sh            # full sweep (14 runs, sequential, slow)
    node bench/aggregate.mjs       # build results/report.md
    node bench/grade.mjs           # build results/quality.json (after rubrics filled)

## Arms
- virgin: isolated CLAUDE_CONFIG_DIR, auth-only, --strict-mcp-config, no hooks/MCP/CLAUDE.md
- stack:  real ~/.claude via `headroom wrap claude`

Primary metric: raw token counts from `-p json` usage. Dollars are synthetic
(Opus rate card in bench/lib/common.sh), since the benchmark runs on a Max plan.
```

- [ ] **Step 3: Create `bench/results/.gitkeep`** (empty file).

- [ ] **Step 4: Commit**

```bash
git add bench/README.md bench/.gitignore bench/results/.gitkeep
git commit -m "bench: scaffold benchmark directory"
```

---

## Task 1: Smoke test — confirm invocations resolve the unknowns

This task runs **two cheap real invocations** (one per arm, trivial prompt) to confirm everything before spending quota on the sweep. No script yet — these are manual confirmations whose answers parameterize Tasks 2–3.

**Files:** none (writes scratch under `/tmp/bench-smoke/`).

- [ ] **Step 1: Locate auth credentials**

Run:
```bash
ls -la ~/.claude/.credentials.json 2>/dev/null && echo FOUND || echo "MISSING - check keychain/other auth"
```
Expected: `FOUND`. If MISSING, the virgin arm cannot authenticate from an isolated config dir — stop and resolve auth (e.g. `claude setup-token`) before proceeding.

- [ ] **Step 2: Build a throwaway virgin config dir**

Run:
```bash
VS=/tmp/bench-smoke/virgin && mkdir -p "$VS"
cp ~/.claude/.credentials.json "$VS"/ 2>/dev/null
printf '%s\n' '{"model":"claude-opus-4-8","effortLevel":"high"}' > "$VS/settings.json"
ls -la "$VS"
```
Expected: dir contains `.credentials.json` and `settings.json`.

- [ ] **Step 3: Virgin smoke run — confirm auth, JSON schema, zero MCP**

Run (cwd must be the repo or anywhere; use `--add-dir` not needed for trivial prompt):
```bash
cd ~/dev/KoffeeMud
ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-8[1m]' \
CLAUDE_CONFIG_DIR=/tmp/bench-smoke/virgin \
command /home/zrom/.local/bin/claude -p "Reply with exactly: OK" \
  --strict-mcp-config --dangerously-skip-permissions \
  --output-format json 2>/tmp/bench-smoke/virgin.err \
| tee /tmp/bench-smoke/virgin.json | jq '{model:.modelUsage, keys:(keys), usage, total_cost_usd, num_turns, result}' 2>/dev/null \
  || cat /tmp/bench-smoke/virgin.json
```
Expected: valid JSON with top-level keys including `usage`, `total_cost_usd`, `num_turns`, `result`. **Record the exact field names** — `aggregate.mjs` depends on them. The `result` should be ~`OK`.

- [ ] **Step 4: Stack smoke run — confirm headroom passes JSON through**

Run:
```bash
cd ~/dev/KoffeeMud
headroom wrap claude -- -p "Reply with exactly: OK" \
  --dangerously-skip-permissions --output-format json 2>/tmp/bench-smoke/stack.err \
| tee /tmp/bench-smoke/stack.json | jq '{keys:(keys), usage, total_cost_usd, num_turns}' 2>/dev/null \
  || cat /tmp/bench-smoke/stack.json
```
Expected: valid JSON with the same schema as virgin. If headroom corrupts stdout (non-JSON banner lines), record how to strip them (e.g. `sed -n '/^{/,$p'`) — `run-stack.sh` will apply that filter.

- [ ] **Step 5: Confirm the effort-override mechanism for the stack arm**

The real `~/.claude/settings.json` has `effortLevel: xhigh`; we need `high`. Test whether `--settings` merges:
```bash
cd ~/dev/KoffeeMud
headroom wrap claude -- -p "Reply with exactly: OK" \
  --settings '{"effortLevel":"high"}' \
  --dangerously-skip-permissions --output-format json 2>/tmp/bench-smoke/stack2.err \
| jq '{num_turns, usage}' 2>/dev/null || cat /tmp/bench-smoke/stack2.json
grep -c 'mcp__' /tmp/bench-smoke/stack2.err /tmp/bench-smoke/stack.err 2>/dev/null || true
```
Decide the override path and **record it**:
- If the run still loads MCP tools (stack behaves normally) AND completes, `--settings '{"effortLevel":"high"}'` **merges** → use it in `run-stack.sh`.
- If MCP servers vanish (merge replaced the settings), fall back: build a full stack config dir copy with effort patched — `CFG=/tmp/bench-stack-cfg; cp -r ~/.claude "$CFG"; jq '.effortLevel="high"' ~/.claude/settings.json > "$CFG/settings.json"` and run with `CLAUDE_CONFIG_DIR="$CFG"` (no `--settings`). Record which path won.

- [ ] **Step 6: Confirm virgin loaded zero MCP**

Run:
```bash
jq -r '.result' /tmp/bench-smoke/virgin.json | head -3
grep -c 'mcp__' /tmp/bench-smoke/virgin.err 2>/dev/null && echo "WARN: virgin saw mcp" || echo "virgin clean (no mcp refs)"
```
Expected: `virgin clean`. If virgin shows MCP refs, add `--setting-sources project,local` is NOT the fix — investigate stray user MCP leaking via `CLAUDE_CONFIG_DIR` not being honored.

- [ ] **Step 7: Record findings in the plan's scratchpad**

Append confirmed values (JSON field names, stdout-strip filter for stack, effort-override path) as an HTML comment block at the top of `bench/lib/common.sh` when you create it in Task 2. No commit (no files yet).

---

## Task 2: Shared lib + virgin runner

**Files:**
- Create: `bench/lib/common.sh`
- Create: `bench/run-virgin.sh`

- [ ] **Step 1: Write `bench/lib/common.sh`**

Use the values confirmed in Task 1. Replace `STACK_JSON_FILTER` / effort-override with what Step 5/6 found.

```bash
#!/usr/bin/env bash
# Shared config for the stack token benchmark. Source me.
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="$BENCH_DIR/results"
KOFFEE="$HOME/dev/KoffeeMud"
CLAUDE_BIN="/home/zrom/.local/bin/claude"
OPUS_MODEL_ENV='claude-opus-4-8[1m]'   # match the stack's ANTHROPIC_DEFAULT_OPUS_MODEL

# Opus rate card, USD per 1M tokens. CONFIRM against current Anthropic pricing.
RATE_INPUT=15.00
RATE_OUTPUT=75.00
RATE_CACHE_WRITE=18.75   # 5-minute cache write (1.25x input)
RATE_CACHE_READ=1.50     # cache read (0.1x input)

# Isolated virgin config dir (auth-only + minimal settings).
build_virgin_dir() {
  local vd="$1"
  mkdir -p "$vd"
  cp "$HOME/.claude/.credentials.json" "$vd"/ 2>/dev/null || {
    echo "FATAL: no ~/.claude/.credentials.json to seed virgin auth" >&2; return 1; }
  printf '%s\n' '{"model":"claude-opus-4-8","effortLevel":"high"}' > "$vd/settings.json"
}

mkdir -p "$RESULTS"
```

- [ ] **Step 2: Write `bench/run-virgin.sh`**

```bash
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
```

- [ ] **Step 3: Validate virgin runner with the baseline prompt**

Run:
```bash
chmod +x bench/run-virgin.sh
bash bench/run-virgin.sh "Reply with exactly: OK" "virgin-baseline-smoke"
jq '{usage, total_cost_usd, num_turns, result}' bench/results/virgin-baseline-smoke.json
```
Expected: parseable JSON, `result` ≈ `OK`, low token counts (this is the fixed tax for virgin — should be small, no MCP schemas).

- [ ] **Step 4: Commit**

```bash
git add bench/lib/common.sh bench/run-virgin.sh
git commit -m "bench: shared lib + virgin runner"
```

---

## Task 3: Stack runner

**Files:**
- Create: `bench/run-stack.sh`

- [ ] **Step 1: Write `bench/run-stack.sh`** (use the effort-override + stdout filter confirmed in Task 1)

```bash
#!/usr/bin/env bash
# Usage: run-stack.sh "<question>" "<output-tag>"
source "$(dirname "$0")/lib/common.sh"
Q="$1"; TAG="$2"

cd "$KOFFEE" || exit 1
# Effort override path confirmed in Task 1 Step 5. Default: --settings merge.
headroom wrap claude -- -p "$Q" \
  --settings '{"effortLevel":"high"}' \
  --dangerously-skip-permissions \
  --output-format json \
  2> "$RESULTS/$TAG.err" \
| sed -n '/^{/,$p' > "$RESULTS/$TAG.json"   # strip any headroom banner before JSON
echo "stack done: $TAG ($(jq -r '.num_turns // "?"' "$RESULTS/$TAG.json" 2>/dev/null) turns)"
```

- [ ] **Step 2: Validate stack runner with the baseline prompt**

Run:
```bash
chmod +x bench/run-stack.sh
bash bench/run-stack.sh "Reply with exactly: OK" "stack-baseline-smoke"
jq '{usage, total_cost_usd, num_turns, result}' bench/results/stack-baseline-smoke.json
```
Expected: parseable JSON. Stack baseline token count should be **much larger** than virgin baseline (MCP schemas + global CLAUDE.md in the system prompt) — this is the headline "fixed tax" number. Eyeball: stack input/cache tokens ≫ virgin.

- [ ] **Step 3: Commit**

```bash
git add bench/run-stack.sh
git commit -m "bench: stack runner via headroom wrap"
```

---

## Task 4: Driver loop

**Files:**
- Create: `bench/drive.sh`

- [ ] **Step 1: Write `bench/drive.sh`**

```bash
#!/usr/bin/env bash
# Full sweep: baselines + 2 tasks x N runs x 2 arms, sequential.
source "$(dirname "$0")/lib/common.sh"
N="${BENCH_N:-3}"

TASK_A="How is the MUD ticker implemented?"
TASK_B="How does CoffeeMud parse and dispatch a player's typed command end-to-end, from input string to executed Command?"
BASE="Reply with exactly: OK"

MANIFEST="$RESULTS/manifest.tsv"
: > "$MANIFEST"
emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$MANIFEST"; }  # arm  task  tag

# Baselines (N=1 each)
bash bench/run-virgin.sh "$BASE" "virgin-baseline"; emit virgin baseline virgin-baseline
bash bench/run-stack.sh  "$BASE" "stack-baseline";  emit stack  baseline stack-baseline

run_set() {
  local q="$1" task="$2"
  for i in $(seq 1 "$N"); do
    bash bench/run-virgin.sh "$q" "virgin-$task-$i"; emit virgin "$task" "virgin-$task-$i"
    bash bench/run-stack.sh  "$q" "stack-$task-$i";  emit stack  "$task" "stack-$task-$i"
  done
}
run_set "$TASK_A" "ticker"
run_set "$TASK_B" "dispatch"
echo "sweep complete -> $MANIFEST"
```

- [ ] **Step 2: Dry-run the driver wiring with N=0-safe check**

Run (does NOT execute claude — just confirms the script parses and the manifest path resolves):
```bash
bash -n bench/drive.sh && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 3: Commit**

```bash
git add bench/drive.sh
git commit -m "bench: sequential driver loop (baseline + 2 tasks, N=3)"
```

- [ ] **Step 4: Execute the full sweep in the background under a Monitor**

This is the expensive step (14 runs, Opus high, minutes each). Launch:
```bash
bash bench/drive.sh > /tmp/bench-drive.log 2>&1 &
```
Then watch `/tmp/bench-drive.log` for each `done:` line and `sweep complete`. Do not start aggregation until `sweep complete` appears and `ls bench/results/*.json | wc -l` ≥ 14.

---

## Task 5: Aggregator

**Files:**
- Create: `bench/aggregate.mjs`

- [ ] **Step 1: Write `bench/aggregate.mjs`** (field names per Task 1 Step 3)

```javascript
#!/usr/bin/env node
// Zero-dep. Reads bench/results/*.json + manifest.tsv -> summary.json + report.md
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RESULTS = join(dirname(fileURLToPath(import.meta.url)), 'results');
const RATE = { input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.5 };

const usageOf = (j) => {
  const u = j.usage || {};
  return {
    input: u.input_tokens || 0,
    output: u.output_tokens || 0,
    cacheWrite: u.cache_creation_input_tokens || 0,
    cacheRead: u.cache_read_input_tokens || 0,
  };
};
const total = (t) => t.input + t.output + t.cacheWrite + t.cacheRead;
const usd = (t) =>
  (t.input * RATE.input + t.output * RATE.output +
   t.cacheWrite * RATE.cacheWrite + t.cacheRead * RATE.cacheRead) / 1e6;
const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b); const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

const manifest = readFileSync(join(RESULTS, 'manifest.tsv'), 'utf8')
  .trim().split('\n').map((l) => { const [arm, task, tag] = l.split('\t'); return { arm, task, tag }; });

const rows = [];
for (const { arm, task, tag } of manifest) {
  let j; try { j = JSON.parse(readFileSync(join(RESULTS, `${tag}.json`), 'utf8')); }
  catch { console.error(`skip unparseable ${tag}`); continue; }
  const t = usageOf(j);
  rows.push({ arm, task, tag, ...t, total: total(t), usd: usd(t),
    turns: j.num_turns ?? null, ms: j.duration_ms ?? null });
}

const groups = {};
for (const r of rows) (groups[`${r.arm}/${r.task}`] ??= []).push(r);

const baseline = {};
for (const arm of ['virgin', 'stack']) {
  const b = groups[`${arm}/baseline`]?.[0];
  baseline[arm] = b ? b.total : 0;
}

const summary = { rateCard: RATE, baseline, groups: {} };
for (const [k, rs] of Object.entries(groups)) {
  const [arm] = k.split('/');
  summary.groups[k] = {
    n: rs.length,
    medTotal: median(rs.map((r) => r.total)),
    medUsd: median(rs.map((r) => r.usd)),
    medInput: median(rs.map((r) => r.input)),
    medOutput: median(rs.map((r) => r.output)),
    medCacheRead: median(rs.map((r) => r.cacheRead)),
    medCacheWrite: median(rs.map((r) => r.cacheWrite)),
    medTurns: median(rs.map((r) => r.turns ?? 0)),
    fixedTax: baseline[arm],
    medWork: median(rs.map((r) => r.total)) - baseline[arm],
  };
}

writeFileSync(join(RESULTS, 'summary.json'), JSON.stringify(summary, null, 2));

const fmt = (n) => n.toLocaleString('en-US');
let md = `# Benchmark report\n\n## Fixed tax (baseline, "Reply OK")\n\n`;
md += `| arm | total tokens |\n|---|---|\n`;
md += `| virgin | ${fmt(baseline.virgin)} |\n| stack | ${fmt(baseline.stack)} |\n\n`;
for (const task of ['ticker', 'dispatch']) {
  md += `## Task: ${task}\n\n| arm | med total | fixed tax | med work | med output | med cache-read | med turns | synth $ |\n|---|---|---|---|---|---|---|---|\n`;
  for (const arm of ['virgin', 'stack']) {
    const g = summary.groups[`${arm}/${task}`]; if (!g) continue;
    md += `| ${arm} | ${fmt(g.medTotal)} | ${fmt(g.fixedTax)} | ${fmt(g.medWork)} | ${fmt(g.medOutput)} | ${fmt(g.medCacheRead)} | ${g.medTurns} | $${g.medUsd.toFixed(4)} |\n`;
  }
  md += `\n`;
}
writeFileSync(join(RESULTS, 'report.md'), md);
console.log('wrote summary.json + report.md');
```

- [ ] **Step 2: Run the aggregator against whatever results exist**

Run:
```bash
node bench/aggregate.mjs && cat bench/results/report.md
```
Expected: `wrote summary.json + report.md` and a rendered table. If `usage` field names differ from Task 1 Step 3, fix `usageOf` accordingly and rerun.

- [ ] **Step 3: Commit**

```bash
git add bench/aggregate.mjs bench/results/report.md bench/results/summary.json
git commit -m "bench: token aggregator + report generator"
```

---

## Task 6: Ground truth + rubrics (CBM-derived)

**Files:**
- Create: `bench/rubrics/ticker.md`
- Create: `bench/rubrics/dispatch.md`

- [ ] **Step 1: Derive ticker ground truth via CBM**

Run (MCP tools, not grep):
```
search_graph(project="home-zrom-dev-KoffeeMud", query="tick tickable service engine thread")
trace_path(project="home-zrom-dev-KoffeeMud", function_name="tick", mode="calls", direction="both")
get_code_snippet(project="home-zrom-dev-KoffeeMud", qualified_name="<the tick loop QN found above>")
```
Capture: the interface(s) (`Tickable`, `TickableGroup`), the engine/thread that drives ticks (`ServiceEngine`/`CMLib` scheduler), the tick interval constant, how objects register to be ticked, and the loop that fires ticks.

- [ ] **Step 2: Write `bench/rubrics/ticker.md`** as a checklist of facts a correct answer must contain

```markdown
# Rubric: "How is the MUD ticker implemented?"

Ground truth (CBM-derived 2026-06-03). Score = facts present / total. Note any
hallucinated class/method not in this list as a deduction.

- [ ] Names the `Tickable` interface as the unit that gets ticked
- [ ] Names `TickableGroup` / the grouping mechanism
- [ ] Identifies the engine/thread driving ticks (e.g. ServiceEngine / scheduler)
- [ ] States the tick interval constant (value + where defined)
- [ ] Describes how objects register/deregister for ticking
- [ ] Describes the tick loop (iterate groups -> call tick())
- [ ] (bonus) Mentions tick status / mishaps handling
<!-- Fill exact class names + the interval value from Step 1 before grading. -->
```

- [ ] **Step 3: Derive dispatch ground truth via CBM**

Run:
```
search_graph(project="home-zrom-dev-KoffeeMud", query="command parse dispatch session input execute")
trace_path(project="home-zrom-dev-KoffeeMud", function_name="<command exec entry>", mode="calls", direction="inbound")
```
Capture: where raw input is read (`Session`/`S_StdSession`), how the command string maps to a `Command` object (`CMClass`/command registry), and how it executes (`Command.execute`).

- [ ] **Step 4: Write `bench/rubrics/dispatch.md`**

```markdown
# Rubric: "How does CoffeeMud parse and dispatch a player command end-to-end?"

Ground truth (CBM-derived 2026-06-03). Score = facts present / total.

- [ ] Names where raw input is read from the player (Session implementation)
- [ ] Describes tokenizing/parsing the input line into command + args
- [ ] Names the command registry / lookup (CMClass or command map)
- [ ] Names the `Command` interface and its execute entry point
- [ ] Describes access/permission or socials/alias handling before execute
- [ ] Traces to actual command execution and result back to the player
<!-- Fill exact class/method names from Step 3 before grading. -->
```

- [ ] **Step 5: Commit**

```bash
git add bench/rubrics/ticker.md bench/rubrics/dispatch.md
git commit -m "bench: CBM-derived fact rubrics for both tasks"
```

---

## Task 7: Blind quality grading

**Files:**
- Create: `bench/grade.mjs`

- [ ] **Step 1: Write `bench/grade.mjs`** — extracts answers, strips arm labels, emits a grading worksheet

```javascript
#!/usr/bin/env node
// Builds a blind grading worksheet: shuffles answers, hides arm identity.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RESULTS = join(dirname(fileURLToPath(import.meta.url)), 'results');
const manifest = readFileSync(join(RESULTS, 'manifest.tsv'), 'utf8')
  .trim().split('\n').map((l) => { const [arm, task, tag] = l.split('\t'); return { arm, task, tag }; });

const answers = [];
for (const { arm, task, tag } of manifest) {
  if (task === 'baseline') continue;
  let j; try { j = JSON.parse(readFileSync(join(RESULTS, `${tag}.json`), 'utf8')); } catch { continue; }
  answers.push({ task, arm, tag, text: (j.result || '').trim() });
}
// Deterministic shuffle by tag hash so the key is reproducible but order hides arm.
const key = answers.map((a, i) => ({ blindId: `ANS-${i}`, ...a }))
  .sort((x, y) => x.tag.localeCompare(y.tag));
writeFileSync(join(RESULTS, 'quality-key.json'),
  JSON.stringify(key.map(({ blindId, task, arm, tag }) => ({ blindId, task, arm, tag })), null, 2));

let ws = `# Blind grading worksheet\n\nGrade each answer against bench/rubrics/<task>.md. Record fact-coverage and hallucinations. Do NOT consult quality-key.json until scores are filled.\n\n`;
for (const a of key) ws += `\n## ${a.blindId} (task: ${a.task})\n\n${a.text}\n\n---\n`;
writeFileSync(join(RESULTS, 'quality-worksheet.md'), ws);
console.log(`wrote worksheet (${key.length} answers) + key`);
```

- [ ] **Step 2: Generate the worksheet**

Run:
```bash
node bench/grade.mjs && head -40 bench/results/quality-worksheet.md
```
Expected: `wrote worksheet (12 answers) + key` (2 tasks × 3 runs × 2 arms).

- [ ] **Step 3: Grade blind, then write `bench/results/quality.json`**

Read `quality-worksheet.md`, score each `ANS-n` against its task rubric (facts covered / total, minus hallucinations). Only after all scores are recorded, read `quality-key.json` to map blindId→arm, and write `bench/results/quality.json`:
```json
{ "ANS-0": { "task": "ticker", "facts": 5, "of": 7, "hallucinations": 0 } }
```

- [ ] **Step 4: Commit**

```bash
git add bench/grade.mjs bench/results/quality.json
git commit -m "bench: blind quality grading scaffold + scores"
```

---

## Task 8: Headroom side-channel reconciliation

**Files:** none (analysis → notes folded into the final report in Task 9).

- [ ] **Step 1: Pull headroom proxy performance for the stack runs**

Run:
```bash
headroom perf 2>&1 | sed -n '1,60p'
```
Capture any reported upstream token / request counts headroom logged for the sweep window.

- [ ] **Step 2: Reconcile one stack run**

Compare the `usage` totals in one `stack-ticker-*.json` against headroom's `perf` numbers for the same window. If headroom reports extra model calls (compression) not in claude's `usage`, the stack's true consumption is **higher** than the `-p json` count. Record the delta (absolute + %) or, if `headroom perf` exposes nothing usable, record "side-channel unmeasurable — stack tokens are a lower bound."

---

## Task 9: Final report + verdict

**Files:**
- Modify: `bench/results/report.md` (append)

- [ ] **Step 1: Merge quality + reconciliation into the report**

Append to `bench/results/report.md`:
- A quality table: per arm per task, median fact-coverage and hallucination count (join `quality.json` via `quality-key.json`).
- The headroom reconciliation note from Task 8.
- A **verdict** paragraph answering the user's premise: did the stack save tokens? Decompose: fixed tax (baseline delta), work tokens per task, output tokens (caveman effect), turn count, and the side-channel caveat. State explicitly where (if anywhere) the stack wins (expected: Task B work-token reduction) and where it loses (expected: Task A, dominated by fixed tax).

- [ ] **Step 2: Sanity-check the verdict against the spec success criteria**

Confirm: 14 runs parsed, 4-way token split per group present, decomposition present, blind quality present. If any missing, fix before claiming done.

- [ ] **Step 3: Commit**

```bash
git add bench/results/report.md
git commit -m "bench: final report + verdict"
```

- [ ] **Step 4: Advisor review**

Call `advisor()` to pressure-test the verdict and methodology before presenting to the user.

---

## Self-review (completed at authoring)

- **Spec coverage:** arms (§1)→Tasks 2–3; tasks (§2)→Task 4 prompts; metric (§3)→Task 5 `usd`/usage; decomposition (§4)→baseline runs + `fixedTax`/`medWork`; quality (§5)→Tasks 6–7; harness/runs (§6)→Tasks 0,4; caveats (§7)→Task 8 + Task 9 verdict. All covered.
- **Placeholder scan:** rubric files intentionally carry `<!-- fill exact names -->` because the names come from a CBM derivation step inside the same task (Task 6 Steps 1/3), not deferred work — acceptable.
- **Type consistency:** `usageOf` field names (`input_tokens`/`output_tokens`/`cache_creation_input_tokens`/`cache_read_input_tokens`) used consistently in `aggregate.mjs`; manifest schema `arm\ttask\ttag` identical in `drive.sh`, `aggregate.mjs`, `grade.mjs`. Rate card identical in `common.sh` and `aggregate.mjs` (single source would be better — noted, but kept inline to preserve zero-dep + standalone scripts).
- **Risk:** `-p json` field names and headroom stdout cleanliness are confirmed empirically in Task 1 before any script depends on them.
