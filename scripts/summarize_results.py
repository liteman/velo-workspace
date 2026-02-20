"""Summarize Velociraptor CLI artifact output.

Parses the concatenated-JSON-array format that `velociraptor artifacts collect`
writes to stdout (possibly interleaved with [ERROR] lines on stderr) and prints
a human-readable summary.

Usage:
    python scripts/summarize_results.py RESULTS_FILE
    python scripts/summarize_results.py RESULTS_FILE --group-by MatchType
    python scripts/summarize_results.py RESULTS_FILE --unique OSPath --sample 5
    cat results.txt | python scripts/summarize_results.py -

Options:
    --group-by COL   Show row counts grouped by distinct values of COL
    --unique COL     List distinct values of COL (repeatable)
    --sample N       Print N sample rows as formatted JSON (default: 0)
    --errors         Show full error lines (otherwise just the count)
    --columns        List all column names found in the result set
"""

import argparse
import json
import re
import sys
from collections import Counter


def parse_velo_output(text: str) -> tuple[list[dict], list[str]]:
    """Parse Velociraptor CLI output into (rows, errors).

    Velociraptor outputs one or more JSON arrays concatenated together,
    with [ERROR] log lines potentially mixed in (when stderr is merged).
    """
    errors = []
    json_lines = []

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[ERROR]"):
            errors.append(stripped)
        else:
            json_lines.append(line)

    clean = "\n".join(json_lines)

    rows = []
    decoder = json.JSONDecoder()
    pos = 0
    length = len(clean)
    while pos < length:
        # Skip whitespace
        while pos < length and clean[pos] in " \t\r\n":
            pos += 1
        if pos >= length:
            break
        try:
            obj, end = decoder.raw_decode(clean, pos)
            if isinstance(obj, list):
                rows.extend(obj)
            elif isinstance(obj, dict):
                rows.append(obj)
            pos = end
        except json.JSONDecodeError:
            # Skip unrecognized character
            pos += 1

    return rows, errors


def print_summary(rows, errors, args):
    # Header
    print(f"Rows: {len(rows)}")
    print(f"Errors: {len(errors)}")

    if not rows:
        if errors and args.errors:
            print("\nError details:")
            for e in errors:
                print(f"  {e}")
        return

    # Columns
    all_cols = set()
    for r in rows:
        all_cols.update(r.keys())
    visible_cols = sorted(c for c in all_cols if not c.startswith("_"))
    hidden_cols = sorted(c for c in all_cols if c.startswith("_"))

    if args.columns:
        print(f"\nColumns: {', '.join(visible_cols)}")
        if hidden_cols:
            print(f"Hidden:  {', '.join(hidden_cols)}")

    # Group by
    for col in args.group_by or []:
        if col not in all_cols:
            print(f"\n--group-by {col}: column not found")
            continue
        counts = Counter(str(r.get(col, "")) for r in rows)
        print(f"\nGroup by {col}:")
        for val, count in counts.most_common():
            label = val if len(val) <= 80 else val[:77] + "..."
            print(f"  {label}: {count}")

    # Unique values
    for col in args.unique or []:
        if col not in all_cols:
            print(f"\n--unique {col}: column not found")
            continue
        values = sorted(set(str(r.get(col, "")) for r in rows))
        print(f"\nUnique {col} ({len(values)}):")
        limit = 25
        for v in values[:limit]:
            label = v if len(v) <= 100 else v[:97] + "..."
            print(f"  {label}")
        if len(values) > limit:
            print(f"  ... and {len(values) - limit} more")

    # Sample rows
    if args.sample and args.sample > 0:
        n = min(args.sample, len(rows))
        print(f"\nSample ({n} of {len(rows)}):")
        for r in rows[:n]:
            # Show only visible columns
            display = {k: v for k, v in r.items() if not k.startswith("_")}
            print(json.dumps(display, indent=2, default=str))

    # Errors
    if errors and args.errors:
        print(f"\nError details ({len(errors)}):")
        shown = errors[:20]
        for e in shown:
            print(f"  {e}")
        if len(errors) > 20:
            print(f"  ... and {len(errors) - 20} more")


def main():
    parser = argparse.ArgumentParser(
        description="Summarize Velociraptor CLI artifact output."
    )
    parser.add_argument(
        "file",
        help="Path to results file, or '-' for stdin",
    )
    parser.add_argument(
        "--group-by",
        action="append",
        metavar="COL",
        help="Group and count rows by column (repeatable)",
    )
    parser.add_argument(
        "--unique",
        action="append",
        metavar="COL",
        help="List distinct values of column (repeatable)",
    )
    parser.add_argument(
        "--sample",
        type=int,
        default=0,
        metavar="N",
        help="Print N sample rows (default: 0)",
    )
    parser.add_argument(
        "--errors",
        action="store_true",
        help="Show full error lines",
    )
    parser.add_argument(
        "--columns",
        action="store_true",
        help="List all column names",
    )

    args = parser.parse_args()

    if args.file == "-":
        text = sys.stdin.read()
    else:
        with open(args.file) as f:
            text = f.read()

    rows, errors = parse_velo_output(text)
    print_summary(rows, errors, args)


if __name__ == "__main__":
    main()
