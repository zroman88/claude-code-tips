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
