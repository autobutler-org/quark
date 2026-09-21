#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Scenarios whose p99 is held to --p99-budget-ms.
LATENCY_GATED_SCENARIOS = {
    "files_list",
    "files_list_nonadmin",
    "files_stat",
    "files_stat_nonadmin",
}

LATENCY_UNITS_MS = {"us": 0.001, "ms": 1.0, "s": 1000.0, "m": 60000.0, "h": 3600000.0}

WRK_SCENARIOS = [
    "albums_list.txt",
    "files_list.txt",
    "files_list_nonadmin.txt",
    "files_stat.txt",
    "files_stat_nonadmin.txt",
    "photos_list.txt",
    "photos_metadata.txt",
    "thumbnails.txt",
]


def fmt(value: str | None, fallback: str = "n/a") -> str:
    return value if value else fallback


def parse_wrk_file(path: Path) -> dict[str, str]:
    stats: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if line.startswith("Requests/sec:"):
            stats["requests_per_sec"] = line.split()[-1]
        elif line.startswith("Transfer/sec:"):
            stats["transfer_per_sec"] = line.split()[-1]
        elif match := re.match(r"^(50|75|90|99)%\s+(\S+)$", line):
            stats[f"p{match.group(1)}"] = match.group(2)
        elif match := re.match(r"^(\d+) requests in ([\d.]+)s,.*$", line):
            stats["requests_total"] = match.group(1)
            stats["duration"] = f"{match.group(2)}s"
        elif line.startswith("Non-2xx or 3xx responses:"):
            stats["non2xx"] = line.split()[-1]
        elif line.startswith("Socket errors:"):
            if match := re.search(r"timeout\s+(\d+)", line):
                stats["timeouts"] = match.group(1)
            errors = []
            for kind, value in re.findall(
                r"(connect|read|write|timeout)\s+(\d+)", line
            ):
                if value != "0":
                    errors.append(f"{kind} {value}")
            if errors:
                stats["socket_errors"] = ", ".join(errors)
    return stats


def latency_ms(value: str) -> float:
    match = re.fullmatch(r"([\d.]+)(us|ms|s|m|h)", value)
    if not match:
        raise ValueError(f"unrecognized wrk latency: {value}")
    return float(match.group(1)) * LATENCY_UNITS_MS[match.group(2)]


def gate_failures(results_dir: Path, p99_budget_ms: float) -> list[str]:
    """Every reason the run in results_dir should fail, empty when it passes."""
    failures: list[str] = []
    for filename in WRK_SCENARIOS:
        path = results_dir / filename
        name = path.stem
        if not path.exists():
            failures.append(f"{name}: no wrk output at {path}")
            continue
        stats = parse_wrk_file(path)
        if stats.get("requests_total", "0") == "0":
            failures.append(f"{name}: no requests completed")
        if (timeouts := stats.get("timeouts", "0")) != "0":
            failures.append(f"{name}: {timeouts} requests timed out")
        if non2xx := stats.get("non2xx"):
            failures.append(f"{name}: {non2xx} non-2xx or 3xx responses")
        if name in LATENCY_GATED_SCENARIOS:
            p99 = stats.get("p99")
            if p99 is None:
                failures.append(f"{name}: no p99 in wrk output")
            elif latency_ms(p99) > p99_budget_ms:
                failures.append(
                    f"{name}: p99 {p99} is over the {p99_budget_ms:g}ms budget"
                )
    return failures


def render_wrk_section(results_dir: Path) -> list[str]:
    lines: list[str] = []
    section_name = results_dir.name.replace("-", " ").title()
    if not section_name.lower().endswith("test"):
        section_name = f"{section_name} Test"
    lines.append(f"### {section_name}")
    lines.append("")

    available_files = [
        results_dir / filename
        for filename in WRK_SCENARIOS
        if (results_dir / filename).exists()
    ]
    if not available_files:
        lines.append("_No wrk outputs were found._")
        lines.append("")
        return lines

    lines.append(
        "| Scenario | Requests | Req/s | P50 | P90 | P99 | Transfer/sec | Notes |"
    )
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |")

    for file_path in available_files:
        stats = parse_wrk_file(file_path)
        notes = []
        if non2xx := stats.get("non2xx"):
            notes.append(f"non-2xx {non2xx}")
        if socket_errors := stats.get("socket_errors"):
            notes.append(socket_errors)

        lines.append(
            "| "
            + file_path.stem.replace("_", " ")
            + " | "
            + f"{fmt(stats.get('requests_total'))} / {fmt(stats.get('duration'))} | "
            + f"{fmt(stats.get('requests_per_sec'))} | "
            + f"{fmt(stats.get('p50'))} | "
            + f"{fmt(stats.get('p90'))} | "
            + f"{fmt(stats.get('p99'))} | "
            + f"{fmt(stats.get('transfer_per_sec'))} | "
            + (", ".join(notes) if notes else "ok")
            + " |"
        )

    upload_status = results_dir / "upload_status_codes.txt"
    if upload_status.exists():
        codes = [
            line.strip()
            for line in upload_status.read_text().splitlines()
            if line.strip()
        ]
        successful = sum(1 for code in codes if code == "200")
        failures = len(codes) - successful
        lines.append("")
        lines.append("#### Upload Stress")
        lines.append("")
        lines.append("| Total uploads | Successful | Failed |")
        lines.append("| ---: | ---: | ---: |")
        lines.append(f"| {len(codes)} | {successful} | {failures} |")

    lines.append("")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render a Markdown performance summary."
    )
    parser.add_argument(
        "--wrk-dir",
        action="append",
        default=[],
        dest="wrk_dirs",
        help="Directory containing wrk result text files.",
    )
    parser.add_argument(
        "--p99-budget-ms",
        type=float,
        help="Fail when any scenario has a timeout or a non-2xx response, or "
        "a files scenario's p99 is over this many milliseconds.",
    )
    args = parser.parse_args()

    print("## Performance Dashboard")
    print("")
    print("A quick summary of the latest load and stress runs.")
    print("")

    for wrk_dir in args.wrk_dirs:
        directory = Path(wrk_dir)
        if directory.exists():
            print("\n".join(render_wrk_section(directory)), end="")

    if args.p99_budget_ms is not None:
        failures = [
            f"{wrk_dir}: {failure}"
            for wrk_dir in args.wrk_dirs
            for failure in gate_failures(Path(wrk_dir), args.p99_budget_ms)
        ]
        for failure in failures:
            print(f"perf gate: {failure}", file=sys.stderr)
        if failures:
            sys.exit(1)


if __name__ == "__main__":
    main()
