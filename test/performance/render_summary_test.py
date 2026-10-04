#!/usr/bin/env python3
"""Tests for the perf gate in render_summary.py. Run with make test/perf/gate."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import render_summary  # noqa: E402

SCRIPT = Path(__file__).parent / "render_summary.py"


def wrk_output(p99: str = "20.00ms", non2xx: int = 0, timeouts: int = 0) -> str:
    lines = [
        "Running 30s test @ http://127.0.0.1:18080",
        "  Latency Distribution",
        "     50%   10.00ms",
        "     75%   12.00ms",
        "     90%   15.00ms",
        f"     99%   {p99}",
        "  1000 requests in 30.00s, 1.00MB read",
    ]
    if timeouts:
        lines.append(f"  Socket errors: connect 0, read 0, write 0, timeout {timeouts}")
    if non2xx:
        lines.append(f"  Non-2xx or 3xx responses: {non2xx}")
    lines += ["Requests/sec:     33.33", "Transfer/sec:     34.13KB"]
    return "\n".join(lines) + "\n"


class GateTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        for filename in render_summary.WRK_SCENARIOS:
            (self.dir / filename).write_text(wrk_output())

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def gate(self) -> tuple[int, str]:
        retry_file = self.dir / "retry.txt"
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--wrk-dir",
                str(self.dir),
                "--p99-budget-ms",
                "400",
                "--retry-file",
                str(retry_file),
            ],
            capture_output=True,
            text=True,
        )
        retry = retry_file.read_text().strip() if retry_file.exists() else ""
        return result.returncode, retry

    def test_passes_a_clean_run(self) -> None:
        self.assertEqual(self.gate(), (0, ""))

    def test_retries_a_p99_over_budget(self) -> None:
        (self.dir / "files_list_nonadmin.txt").write_text(wrk_output(p99="409.66ms"))
        self.assertEqual(
            self.gate(), (render_summary.EXIT_RETRY, "files_list_nonadmin")
        )

    def test_retries_timeouts(self) -> None:
        (self.dir / "albums_list.txt").write_text(wrk_output(timeouts=5))
        (self.dir / "files_list.txt").write_text(wrk_output(p99="638.33ms"))
        self.assertEqual(
            self.gate(), (render_summary.EXIT_RETRY, "albums_list files_list")
        )

    def test_fails_non2xx_without_a_retry(self) -> None:
        # The 401s of #2743 were a real server bug, not noise.
        (self.dir / "files_stat.txt").write_text(wrk_output(non2xx=48))
        self.assertEqual(self.gate(), (1, ""))

    def test_fails_without_a_retry_when_any_failure_is_hard(self) -> None:
        (self.dir / "files_list.txt").write_text(wrk_output(p99="638.33ms"))
        (self.dir / "thumbnails.txt").write_text(wrk_output(non2xx=69))
        self.assertEqual(self.gate(), (1, ""))

    def test_fails_a_missing_scenario_without_a_retry(self) -> None:
        (self.dir / "photos_list.txt").unlink()
        self.assertEqual(self.gate(), (1, ""))


if __name__ == "__main__":
    unittest.main()
