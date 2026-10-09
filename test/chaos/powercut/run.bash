#! /usr/bin/env bash

# Cuts the power under Quark's upload and vault write paths and checks what is
# left (#2517). Each case mounts a fresh LazyFS, starts the powercut writer on
# it, and arms a crash fault: at the next file-system call matching the fault,
# LazyFS drops everything that was never flushed and kills itself, which is what
# a power cut does to the page cache. The checker then reads the directory
# LazyFS was backed by -- exactly what reached the disk -- against the writer's
# ledger of acknowledged operations.
#
# Usually run through `make test/chaos/powercut`, which builds the writer and
# runs this inside the LazyFS image. To run it directly:
#
#   LAZYFS=/path/to/lazyfs POWERCUT=/path/to/powercut test/chaos/powercut/run.bash
#
# POWERCUT_ROUNDS  rounds per case, each arming its fault at a different moment (default 3)
# WORK_DIR         where per-case logs and the summary land (default test-results/powercut)

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

LAZYFS="${LAZYFS:-lazyfs}"
POWERCUT="${POWERCUT:-powercut}"
ROUNDS="${POWERCUT_ROUNDS:-3}"
WORK_DIR="${WORK_DIR:-test-results/powercut}"

for tool in "$LAZYFS" "$POWERCUT" fusermount3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool is not on PATH. Run this through 'make test/chaos/powercut', which provides it." >&2
        exit 1
    fi
done

# scenario|fault. A fault names the call LazyFS crashes at, and whether before or
# after it runs. Paths match as substrings; a rename or link names both ends.
CASES=(
    # An upload streaming into its temp, before anything is flushed.
    "upload|timing=after::op=write::from_rgx=/\.vfs-write-"
    # The instant an upload gets its real name: the window that used to leave
    # an empty file behind.
    "upload|timing=after::op=rename::from_rgx=/\.vfs-write-::to_rgx=/file-"
    # A resumable upload linked into place.
    "upload|timing=after::op=link::from_rgx=/upload-::to_rgx=/file-"
    # A device-serial upload, or any write refusing a taken name, linked into
    # place from its temp.
    "upload|timing=after::op=link::from_rgx=/\.vfs-write-::to_rgx=/file-"
    # Any flush at all.
    "upload|timing=before::op=fsync::from_rgx=/"
    # A vault transaction whose journal is on disk and whose database is not.
    "vault|timing=after::op=fsync::from_rgx=vault\.db-journal"
    # Halfway through writing pages into the vault database.
    "vault|timing=after::op=write::from_rgx=vault\.db$"
    # The commit point: the journal is about to be deleted.
    "vault|timing=before::op=unlink::from_rgx=vault\.db-journal"
)

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
SUMMARY="$WORK_DIR/summary.txt"
failures=0

lazyfs_pid=""
cleanup() {
    if [[ -n "$lazyfs_pid" ]]; then
        kill -9 "$lazyfs_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# run_case <name> <scenario> <fault> <delay>
run_case() {
    local name="$1" scenario="$2" fault="$3" delay="$4"
    local dir="$WORK_DIR/$name"
    local root="$dir/root" mnt="$dir/mnt" fifo="$dir/faults.fifo"
    mkdir -p "$root" "$mnt"

    cat >"$dir/lazyfs.toml" <<EOF
[faults]
fifo_path="$fifo"
[cache]
apply_eviction=false
[cache.simple]
custom_size="512mb"
blocks_per_page=1
[filesystem]
log_all_operations=false
logfile="$dir/lazyfs.log"
EOF

    "$LAZYFS" "$mnt" --config-path "$dir/lazyfs.toml" \
        -o allow_other -o modules=subdir -o subdir="$root" -f >"$dir/lazyfs.out" 2>&1 &
    lazyfs_pid=$!
    # Killing LazyFS is the point of every case; keep the shell from announcing it.
    disown "$lazyfs_pid"
    for _ in $(seq 1 150); do
        mountpoint -q "$mnt" && [[ -p "$fifo" ]] && break
        sleep 0.2
    done
    if ! mountpoint -q "$mnt"; then
        echo "LazyFS did not mount $mnt; see $dir/lazyfs.out" >&2
        cat "$dir/lazyfs.out" >&2
        exit 1
    fi

    timeout 120 "$POWERCUT" write "$scenario" "$mnt" "$dir/ledger" >"$dir/write.log" 2>&1 &
    local writer_pid=$!
    sleep "$delay"
    if kill -0 "$lazyfs_pid" 2>/dev/null; then
        echo "lazyfs::crash::$fault" >"$fifo"
    fi
    wait "$writer_pid" || true

    # The fault fired and LazyFS is gone, or the writer ran out of work first:
    # either way, killing LazyFS now is the power cut, since everything it had
    # not flushed lives only in its memory.
    local cut="at the fault"
    if kill -0 "$lazyfs_pid" 2>/dev/null; then
        cut="after the writer finished"
        kill -9 "$lazyfs_pid"
    fi
    while kill -0 "$lazyfs_pid" 2>/dev/null; do
        sleep 0.1
    done
    lazyfs_pid=""
    fusermount3 -uz "$mnt" 2>/dev/null || true

    local verdict="PASS"
    if ! "$POWERCUT" check "$scenario" "$root" "$dir/ledger" >"$dir/check.log" 2>&1; then
        verdict="FAIL"
        failures=$((failures + 1))
    fi
    printf '%-4s %-22s cut %-25s %s\n' "$verdict" "$name" "$cut" \
        "$(grep -m 1 -E '^(upload|vault):' "$dir/check.log" || tail -n 1 "$dir/check.log")" | tee -a "$SUMMARY"
    if [[ "$verdict" == "FAIL" ]]; then
        sed -n '1,12s/^/     /p' "$dir/check.log"
    fi

    # Keep the logs and ledger, and the disk image only where a case failed. What
    # stays is left readable to whoever owns the results directory outside the
    # container: the writer's files are 0600 and root's, and a FIFO is nothing
    # an artifact upload can read.
    rm -f "$fifo"
    rmdir "$mnt" 2>/dev/null || true
    if [[ "$verdict" == "PASS" ]]; then
        rm -rf "$root"
    fi
    chmod -R a+rX "$dir"
}

for round in $(seq 1 "$ROUNDS"); do
    for i in "${!CASES[@]}"; do
        IFS='|' read -r scenario fault <<<"${CASES[$i]}"
        # Spread the moment each fault is armed across rounds, so the cut lands
        # on a different operation each time.
        delay="$(awk -v r="$round" -v c="$i" 'BEGIN { printf "%.1f", 0.3 + ((r * 7 + c * 3) % 20) / 10 }')"
        run_case "r${round}-c${i}-${scenario}" "$scenario" "$fault" "$delay"
    done
done

echo
if ((failures > 0)); then
    echo "$failures case(s) left state behind that a power cut must not. Logs: $WORK_DIR"
    exit 1
fi
echo "Every case survived its power cut. Logs: $WORK_DIR"
