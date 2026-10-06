#!/usr/bin/env bash
# Runs test.sh and holds the result to the perf gate. A failure that runner
# noise alone can produce (a timeout, a p99 over budget) reruns just those
# scenarios once, and only a second failure fails the gate; anything else fails
# at once (#2743). Usage: run_gated.sh <p99 budget ms>, with test.sh's
# environment, WORK_DIR included.
set -euo pipefail

budget="$1"
retry_file="$WORK_DIR/retry.txt"

./test/performance/test.sh

status=0
python3 ./test/performance/render_summary.py --wrk-dir "$WORK_DIR" \
  --p99-budget-ms "$budget" --retry-file "$retry_file" || status=$?
if [[ "$status" != 3 ]]; then
  exit "$status"
fi

scenarios="$(cat "$retry_file")"
# The first attempt stays in the artifacts next to the rerun.
for name in $scenarios; do
  mv "$WORK_DIR/$name.txt" "$WORK_DIR/$name.attempt1.txt"
done
echo "Rerunning once: $scenarios"
PERF_SCENARIOS="$scenarios" ./test/performance/test.sh
python3 ./test/performance/render_summary.py --wrk-dir "$WORK_DIR" \
  --p99-budget-ms "$budget"
