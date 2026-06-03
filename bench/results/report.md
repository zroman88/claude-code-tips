# Benchmark report — virgin Opus 4.8 vs full stack

_Primary metric: total tokens processed (cache-invariant). Synthetic $ uses Opus rates (input $15, output $75, 1h-write $30, 5m-write $18.75, cache-read $1.5 per Mtok) and reflects each run's real cache state._

## Fixed tax — baseline "Reply OK" (system prompt + tools + CLAUDE.md/MCP)

| arm | total tokens |
|---|--:|
| virgin | 47,114 |
| stack | 85,182 |
| **stack ÷ virgin** | **1.81×** |

## Task: ticker

| arm | med total tok | fixed tax | med work tok | med output | med turns | synth $/run | CC $/run |
|---|--:|--:|--:|--:|--:|--:|--:|
| virgin | 460,628 | 47,114 | 413,514 | 3,212 | 11 | $2.0670 | $0.5186 |
| stack | 740,726 | 85,182 | 655,544 | 3,915 | 12 | $3.0414 | $0.8261 |
| **stack ÷ virgin** | **1.61×** | | | | | | |

## Task: dispatch

| arm | med total tok | fixed tax | med work tok | med output | med turns | synth $/run | CC $/run |
|---|--:|--:|--:|--:|--:|--:|--:|
| virgin | 597,707 | 47,114 | 550,593 | 5,153 | 24 | $2.9580 | $1.1591 |
| stack | 1,491,207 | 85,182 | 1,406,025 | 7,900 | 24 | $4.7515 | $1.3381 |
| **stack ÷ virgin** | **2.49×** | | | | | | |

## Answer quality (blind, fact-coverage vs CBM ground truth)

| arm | task | mean facts | final-answer words | hallucinations |
|---|---|--:|--:|--:|
| virgin | ticker | 7 / 7 | 499 | 0 |
| stack | ticker | 7 / 7 | 348 | 0 |
| virgin | dispatch | 6 / 6 | 475 | 0 |
| stack | dispatch | 6 / 6 | 411 | 0 |

Both arms achieved full fact coverage on every run by the automated keyword check. Because a
keyword check saturates (everyone scores 100%), a matched pair per task was also **read by
hand**: both arms' answers are substantively correct and complete — they trace the real
classes (`ServiceEngine`/`StdTickGroup`/`StdTickClient`; `DefaultSession.mainLoop`→
`EnglishParser.findCommand`→`CMClass.commandWords`→`doCommand`→`execute`), both even more
precisely than the rubric's own guess. If anything **virgin's ticker answer is marginally more
comprehensive** (adds the watchdog/`checkHealth`, shutdown, suspend/resume). The stack's final
answers are terser (caveman) but no less correct. Conclusion: **no quality gap — and the small
edge, if any, is virgin's.**

## Headroom side-channel (`headroom perf`, 168h window, 666 reqs)

- Headroom's actual token compression: **1.3%** (272,504 saved of 21.6M). Its `content_router`
  averages **0.2%** reduction — 82% of tool outputs are `<50 words` (skipped), 15% Read/Glob
  (excluded), only 32 ever compressed.
- Overhead is **latency only** (116 ms avg), **no extra model calls** → the `-p json` token
  counts above are accurate, **not an undercount**. The stack arm is not penalised by a hidden
  side-channel; if anything it is measured generously.

## Verdict

**The user's observation is confirmed: on both tasks the stack consumes more and costs more,
for no better answer quality** (read-confirmed tie; virgin marginally richer on the ticker).

| | ticker (focused — tight, robust) | dispatch (broad — high variance) |
|---|--:|--:|
| **cost — CC `total_cost_usd`, stack ÷ virgin (median)** | **1.59×** | **~1.15×** |
| total tokens, stack ÷ virgin (median) | 1.61× | 2.49× |
| per-run token range (virgin vs stack) | 371–486k vs 701–908k — **non-overlapping** | 201k–1.15M vs 1.36–1.75M — **non-overlapping** |
| median turns (virgin → stack) | 11 → 12 | 24 → 24 (virgin spread 4–30) |
| answer quality (read-confirmed) | tie | tie (virgin slightly richer) |

**Lead on the ticker result** — it is the user's actual question and the tight, robust one:
the stack's *best* run (701k tokens) still exceeds virgin's *worst* (486k). The cost headline
is CC's own estimate (**1.59×**); the token ratio (1.61×) explains the mechanism but, on Max,
is not what you pay.

**Dispatch is directionally identical but noisier.** Virgin's three dispatch runs ranged
201k–1.15M tokens (4–30 turns), so the 2.49× median could shift on a rerun. Even so the
direction is solid — the ranges don't overlap (stack's *worst* dispatch run, 1.36M, beats
virgin's *best*, 1.15M). By **cost** the dispatch gap is only ~1.15×, because the stack's token
surplus is largely *cheap* `cache_read`, not new work.

**Mechanism.** The stack pays a **1.81× fixed tax** every turn (85k vs 47k tokens of system
prompt = MCP tool schemas + the forced-CBM-first global `CLAUDE.md`). That prefix is re-read
as `cache_read` on every one of the 11–24 turns, so the gap compounds with conversation
length. The stack also emits more total output tokens (more tool-call turns) despite terser
final answers. Headroom's ~1% compression does not offset the overhead of the MCP layer it
ships with.

**The stack's theoretical edge did not appear.** The pitch — CBM `trace_path` replacing
grep→read→grep, cutting turns — did not materialise: stack turn counts were **equal or higher**
than virgin on both tasks (the gate hooks forced extra discovery tool calls before answering).
By cost, dispatch is closer (1.15×) than by tokens (2.49×) only because the stack's surplus is
largely *cheap* `cache_read` tokens, not because it did less work.

**What this benchmark does NOT measure (be fair).** The stack's real design goal is
**context-window preservation across long, multi-task sessions** — keeping huge raw outputs
out of the conversation so a session runs longer before compaction and the model reasons over
a cleaner context. A single one-shot `claude -p` question cannot capture that benefit; here the
MCP fixed tax is pure overhead with nothing large to amortise. For interactive single-question
or short Q&A workloads on an indexed repo, **virgin Claude Code is cheaper and equally good.**

**Caveats:** N=3 (directional, not publication-grade); one codebase, two questions; synthetic $
priced off published Opus rates (Max plan has no per-request dollars); the total-token metric is
cache-invariant and solid, the $ figures are cache-state-dependent; the one-time CBM index build
is not charged per run.

