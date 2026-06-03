#!/usr/bin/env bash
# Full sweep: baselines + 2 tasks x N runs x 2 arms, sequential.
# Total tokens are cache-invariant (verified), so natural back-to-back runs are
# fine for the primary metric. Baselines run first to capture the prefix.
source "$(dirname "$0")/lib/common.sh"
N="${BENCH_N:-3}"

TASK_A="How is the MUD ticker implemented?"
TASK_B="How does CoffeeMud parse and dispatch a player's typed command end-to-end, from input string to executed Command?"
BASE="Reply with exactly: OK"

MANIFEST="$RESULTS/manifest.tsv"
: > "$MANIFEST"
emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$MANIFEST"; }  # arm  task  tag

echo "[drive] baselines"
bash "$BENCH_DIR/run-virgin.sh" "$BASE" "virgin-baseline"; emit virgin baseline virgin-baseline
bash "$BENCH_DIR/run-stack.sh"  "$BASE" "stack-baseline";  emit stack  baseline stack-baseline

run_set() {
  local q="$1" task="$2" i
  for i in $(seq 1 "$N"); do
    echo "[drive] $task run $i/$N"
    bash "$BENCH_DIR/run-virgin.sh" "$q" "virgin-$task-$i"; emit virgin "$task" "virgin-$task-$i"
    bash "$BENCH_DIR/run-stack.sh"  "$q" "stack-$task-$i";  emit stack  "$task" "stack-$task-$i"
  done
}
run_set "$TASK_A" "ticker"
run_set "$TASK_B" "dispatch"
echo "[drive] sweep complete -> $MANIFEST"
