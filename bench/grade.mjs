#!/usr/bin/env node
// Builds a blind grading worksheet: extracts answers, hides arm identity.
// Grade ANS-n against bench/rubrics/<task>.md WITHOUT consulting quality-key.json.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RESULTS = join(dirname(fileURLToPath(import.meta.url)), 'results');
const manifest = readFileSync(join(RESULTS, 'manifest.tsv'), 'utf8')
  .trim().split('\n').filter(Boolean)
  .map((l) => { const [arm, task, tag] = l.split('\t'); return { arm, task, tag }; });

const answers = [];
for (const { arm, task, tag } of manifest) {
  if (task === 'baseline') continue;
  let j; try { j = JSON.parse(readFileSync(join(RESULTS, `${tag}.json`), 'utf8')); } catch { continue; }
  answers.push({ task, arm, tag, text: (j.result || '').trim() });
}
// Sort by tag so order is deterministic and does not reveal arm grouping.
const key = answers.map((a, i) => ({ blindId: `ANS-${i}`, ...a }))
  .sort((x, y) => x.tag.localeCompare(y.tag))
  .map((a, i) => ({ ...a, blindId: `ANS-${i}` }));

writeFileSync(join(RESULTS, 'quality-key.json'),
  JSON.stringify(key.map(({ blindId, task, arm, tag }) => ({ blindId, task, arm, tag })), null, 2));

let ws = `# Blind grading worksheet\n\nGrade each answer against bench/rubrics/<task>.md (fact coverage minus hallucinations). Do NOT open quality-key.json until every score is filled.\n`;
for (const a of key) ws += `\n## ${a.blindId} — task: ${a.task}\n\n${a.text}\n\n---\n`;
writeFileSync(join(RESULTS, 'quality-worksheet.md'), ws);
console.log(`wrote worksheet (${key.length} answers) + key`);
