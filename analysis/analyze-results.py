#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path
import csv


def load_result(path: Path):
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    meta = data["metadata"]
    results = data["hyperfine"]["results"]

    left = results[0]
    right = results[1]

    left_variant = meta["left_variant"]
    right_variant = meta["right_variant"]

    if left_variant == "lsr":
        lsr = left
        other = right
        other_variant = right_variant
    elif right_variant == "lsr":
        lsr = right
        other = left
        other_variant = left_variant
    else:
        raise ValueError(f"No lsr variant in {path}")

    lsr_mean = lsr["mean"]
    other_mean = other["mean"]

    lsr_std = lsr["stddev"]
    other_std = other["stddev"]

    # speedup > 1 means LSR is faster
    speedup = other_mean / lsr_mean

    # Error propagation for ratio: r = a / b
    speedup_std = speedup * math.sqrt(
        (other_std / other_mean) ** 2 +
        (lsr_std / lsr_mean) ** 2
    )

    percent = (speedup - 1.0) * 100.0
    percent_std = speedup_std * 100.0

    return {
        "timestamp": meta["timestamp"],
        "suite": meta["suite"],
        "benchmark": meta["benchmark"],
        "comparison": meta["comparison"],
        "other_variant": other_variant,
        "lsr_mean": lsr_mean,
        "lsr_std": lsr_std,
        "other_mean": other_mean,
        "other_std": other_std,
        "speedup": speedup,
        "speedup_std": speedup_std,
        "percent": percent,
        "percent_std": percent_std,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results_dir", help="Example: results/2026-05-05_15-33-05")
    parser.add_argument("--csv", default=None, help="Optional CSV output path")
    args = parser.parse_args()

    root = Path(args.results_dir)

    rows = []
    for path in sorted(root.rglob("*.json")):
        if path.name.endswith(".raw.json"):
            continue
        try:
            rows.append(load_result(path))
        except Exception as e:
            print(f"Skipping {path}: {e}")

    rows.sort(key=lambda r: (r["suite"], r["other_variant"], r["benchmark"]))

    print(f"{'Suite':<12} {'Comparison':<18} {'Benchmark':<32} {'LSR change':>22} {'Speedup':>18}")
    print("-" * 110)

    for r in rows:
        sign = "faster" if r["percent"] >= 0 else "slower"
        print(
            f"{r['suite']:<12} "
            f"{r['comparison']:<18} "
            f"{r['benchmark']:<32} "
            f"{abs(r['percent']):>8.2f}% ± {r['percent_std']:<6.2f} {sign:<6} "
            f"{r['speedup']:>8.3f} ± {r['speedup_std']:<7.3f}"
        )

    if args.csv:
        out = Path(args.csv)
        out.parent.mkdir(parents=True, exist_ok=True)

        with out.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)

        print(f"\nWrote CSV: {out}")


if __name__ == "__main__":
    main()
