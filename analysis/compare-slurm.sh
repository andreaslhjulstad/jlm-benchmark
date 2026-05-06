#!/usr/bin/env bash
#SBATCH --partition=CPUQ
#SBATCH --account=share-ie-idi
#SBATCH --job-name=jlm-compare
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=48:00:00
#SBATCH -o slurm-log/compare.%A.%a.out

set -euo pipefail

SELF=./analysis/compare-slurm.sh

if [ -z "${APPTAINER_NAME+x}" ]; then
    exec apptainer exec "$APPTAINER_CONTAINER" "$SELF" "$@"
fi

RUN_TIMESTAMP="${RUN_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"

SUITES=(
    "polybench"
    "embench"
)

COMPARISONS=(
    "lsr no-lsr"
    "lsr clang-o3"
    "lsr m2r"
)

JOBS=()

for SUITE in "${SUITES[@]}"; do
    for COMPARISON in "${COMPARISONS[@]}"; do
        read -r LEFT_VARIANT RIGHT_VARIANT <<< "$COMPARISON"

        LEFT_ROOT="./build/${SUITE}/${LEFT_VARIANT}"

        if [[ ! -d "$LEFT_ROOT" ]]; then
            echo "Skipping missing root: $LEFT_ROOT"
            continue
        fi

        while IFS= read -r BENCH_DIR; do
            BENCHMARK="$(basename "$BENCH_DIR")"
            JOBS+=("${SUITE} ${LEFT_VARIANT} ${RIGHT_VARIANT} ${BENCHMARK}")
        done < <(
            find "$LEFT_ROOT" -mindepth 1 -maxdepth 1 -type d | sort
        )
    done
done

if [[ "${#JOBS[@]}" -eq 0 ]]; then
    echo "No comparison jobs found."
    exit 1
fi

if [[ "${SLURM_ARRAY_TASK_ID}" -ge "${#JOBS[@]}" ]]; then
    echo "Array task ${SLURM_ARRAY_TASK_ID} is out of range. Jobs: ${#JOBS[@]}"
    exit 1
fi

read -r SUITE LEFT_VARIANT RIGHT_VARIANT BENCHMARK <<< "${JOBS[$SLURM_ARRAY_TASK_ID]}"

COMPARE_NAME="${LEFT_VARIANT}-vs-${RIGHT_VARIANT}"

LEFT_ROOT="./build/${SUITE}/${LEFT_VARIANT}"
RIGHT_ROOT="./build/${SUITE}/${RIGHT_VARIANT}"

LEFT_BINARY="${LEFT_ROOT}/${BENCHMARK}/${BENCHMARK}-clang-link-out"
RIGHT_BINARY="${RIGHT_ROOT}/${BENCHMARK}/${BENCHMARK}-clang-link-out"

RESULT_DIR="results/${RUN_TIMESTAMP}/${SUITE}/${COMPARE_NAME}"
mkdir -p "$RESULT_DIR"

RESULT_JSON="${RESULT_DIR}/${BENCHMARK}.json"
RAW_JSON="${RESULT_DIR}/${BENCHMARK}.raw.json"

echo "Timestamp:  ${RUN_TIMESTAMP}"
echo "Suite:      ${SUITE}"
echo "Benchmark:  ${BENCHMARK}"
echo "Compare:    ${LEFT_VARIANT} vs ${RIGHT_VARIANT}"
echo "Left:       ${LEFT_BINARY}"
echo "Right:      ${RIGHT_BINARY}"
echo "Result:     ${RESULT_JSON}"

if [[ ! -x "$LEFT_BINARY" ]]; then
    echo "Missing left binary: $LEFT_BINARY"
    exit 1
fi

if [[ ! -x "$RIGHT_BINARY" ]]; then
    echo "Missing right binary: $RIGHT_BINARY"
    exit 1
fi

if [[ "$SUITE" == "polybench" ]]; then
    LEFT_OUT="${RESULT_DIR}/${BENCHMARK}.${LEFT_VARIANT}.out"
    RIGHT_OUT="${RESULT_DIR}/${BENCHMARK}.${RIGHT_VARIANT}.out"

    "$LEFT_BINARY" 2>&1 | sed -n '/==BEGIN/,/==END/p' > "$LEFT_OUT"
    "$RIGHT_BINARY" 2>&1 | sed -n '/==BEGIN/,/==END/p' > "$RIGHT_OUT"

    diff "$LEFT_OUT" "$RIGHT_OUT"
else
    "$LEFT_BINARY" > /dev/null
    "$RIGHT_BINARY" > /dev/null
fi

hyperfine \
    --prepare=true \
    --warmup 3 \
    --runs 20 \
    --shell=none \
    --ignore-failure \
    --export-json "$RAW_JSON" \
    "$LEFT_BINARY" \
    "$RIGHT_BINARY"

python3 - "$RAW_JSON" "$RESULT_JSON" <<EOF
import json
import socket
import sys

raw_path = sys.argv[1]
out_path = sys.argv[2]

with open(raw_path, "r", encoding="utf-8") as f:
    raw = json.load(f)

out = {
    "metadata": {
        "timestamp": "${RUN_TIMESTAMP}",
        "suite": "${SUITE}",
        "benchmark": "${BENCHMARK}",
        "left_variant": "${LEFT_VARIANT}",
        "right_variant": "${RIGHT_VARIANT}",
        "comparison": "${COMPARE_NAME}",
        "left_binary": "${LEFT_BINARY}",
        "right_binary": "${RIGHT_BINARY}",
        "hostname": socket.gethostname(),
        "slurm_job_id": "${SLURM_JOB_ID:-}",
        "slurm_array_job_id": "${SLURM_ARRAY_JOB_ID:-}",
        "slurm_array_task_id": "${SLURM_ARRAY_TASK_ID:-}"
    },
    "hyperfine": raw
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2)
EOF

rm "$RAW_JSON"

echo "Done: $RESULT_JSON"
