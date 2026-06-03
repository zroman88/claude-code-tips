#!/usr/bin/env node
// Zero-dep. Reads bench/results/*.json + manifest.tsv -> summary.json + report.md
// Primary metric = total tokens (cache-invariant: warming only moves tokens between
// the cache_creation and cache_read buckets; the sum processed is identical).
// Synthetic $ is secondary and cache-state-dependent (priced per real buckets below).
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RESULTS = join(dirname(fileURLToPath(import.meta.url)), 'results');
// Opus rate card, USD per 1M tokens. CONFIRM against current Anthropic pricing.
const RATE = { input: 15.0, output: 75.0, write1h: 30.0, write5m: 18.75, read: 1.5 };

const usageOf = (j) => {
  const u = j.usage || {};
  const cc = u.cache_creation || {};
  return {
    input: u.input_tokens || 0,
    output: u.output_tokens || 0,
    cacheCreate: u.cache_creation_input_tokens || 0,
    cacheRead: u.cache_read_input_tokens || 0,
    e1h: cc.ephemeral_1h_input_tokens || 0,
    e5m: cc.ephemeral_5m_input_tokens || 0,
  };
};
// Cache-invariant total: every token the API processed this run.
const total = (t) => t.input + t.output + t.cacheCreate + t.cacheRead;
// Synthetic cost from the real buckets (reflects this run's actual cache state).
const usd = (t) =>
  (t.input * RATE.input + t.output * RATE.output +
   t.e1h * RATE.write1h + t.e5m * RATE.write5m + t.cacheRead * RATE.read) / 1e6;
const median = (xs) => {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b); const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

const manifest = readFileSync(join(RESULTS, 'manifest.tsv'), 'utf8')
  .trim().split('\n').filter(Boolean)
  .map((l) => { const [arm, task, tag] = l.split('\t'); return { arm, task, tag }; });

const rows = [];
for (const { arm, task, tag } of manifest) {
  let j; try { j = JSON.parse(readFileSync(join(RESULTS, `${tag}.json`), 'utf8')); }
  catch { console.error(`skip unparseable ${tag}`); continue; }
  const t = usageOf(j);
  rows.push({ arm, task, tag, ...t, total: total(t), usd: usd(t),
    ccUsd: j.total_cost_usd ?? null, turns: j.num_turns ?? null });
}

const groups = {};
for (const r of rows) (groups[`${r.arm}/${r.task}`] ??= []).push(r);

const baseline = {};
for (const arm of ['virgin', 'stack']) baseline[arm] = groups[`${arm}/baseline`]?.[0]?.total ?? 0;

const summary = { rateCard: RATE, baseline, groups: {} };
for (const [k, rs] of Object.entries(groups)) {
  const [arm] = k.split('/');
  summary.groups[k] = {
    n: rs.length,
    medTotal: median(rs.map((r) => r.total)),
    medInput: median(rs.map((r) => r.input)),
    medOutput: median(rs.map((r) => r.output)),
    medCacheCreate: median(rs.map((r) => r.cacheCreate)),
    medCacheRead: median(rs.map((r) => r.cacheRead)),
    medUsd: median(rs.map((r) => r.usd)),
    medCcUsd: median(rs.map((r) => r.ccUsd ?? 0)),
    medTurns: median(rs.map((r) => r.turns ?? 0)),
    fixedTax: baseline[arm],
    medWork: median(rs.map((r) => r.total)) - baseline[arm],
    runs: rs.map((r) => ({ tag: r.tag, total: r.total, turns: r.turns,
      cacheRead: r.cacheRead, usd: +r.usd.toFixed(4), ccUsd: r.ccUsd })),
  };
}
writeFileSync(join(RESULTS, 'summary.json'), JSON.stringify(summary, null, 2));

const fmt = (n) => Math.round(n).toLocaleString('en-US');
let md = `# Benchmark report — virgin Opus 4.8 vs full stack\n\n`;
md += `_Primary metric: total tokens processed (cache-invariant). Synthetic $ uses Opus rates `;
md += `(input $15, output $75, 1h-write $30, 5m-write $18.75, cache-read $1.5 per Mtok) and reflects each run's real cache state._\n\n`;
md += `## Fixed tax — baseline "Reply OK" (system prompt + tools + CLAUDE.md/MCP)\n\n`;
md += `| arm | total tokens |\n|---|--:|\n`;
md += `| virgin | ${fmt(baseline.virgin)} |\n| stack | ${fmt(baseline.stack)} |\n`;
if (baseline.virgin) md += `| **stack ÷ virgin** | **${(baseline.stack / baseline.virgin).toFixed(2)}×** |\n`;
md += `\n`;
for (const task of ['ticker', 'dispatch']) {
  md += `## Task: ${task}\n\n`;
  md += `| arm | med total tok | fixed tax | med work tok | med output | med turns | synth $/run | CC $/run |\n`;
  md += `|---|--:|--:|--:|--:|--:|--:|--:|\n`;
  for (const arm of ['virgin', 'stack']) {
    const g = summary.groups[`${arm}/${task}`]; if (!g) continue;
    md += `| ${arm} | ${fmt(g.medTotal)} | ${fmt(g.fixedTax)} | ${fmt(g.medWork)} | ${fmt(g.medOutput)} | ${g.medTurns} | $${g.medUsd.toFixed(4)} | $${(g.medCcUsd).toFixed(4)} |\n`;
  }
  const v = summary.groups[`virgin/${task}`], s = summary.groups[`stack/${task}`];
  if (v && s && v.medTotal) md += `| **stack ÷ virgin** | **${(s.medTotal / v.medTotal).toFixed(2)}×** | | | | | | |\n`;
  md += `\n`;
}
writeFileSync(join(RESULTS, 'report.md'), md);
console.log(`aggregated ${rows.length} runs -> summary.json + report.md`);
