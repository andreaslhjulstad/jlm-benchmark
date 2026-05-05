#!/usr/bin/env bash
set -eu

SUITE="${1:?Usage: ./compare.sh <suite> <left-variant> <right-variant>}"
LEFT_VARIANT="${2:?Usage: ./compare.sh <suite> <left-variant> <right-variant>}"
RIGHT_VARIANT="${3:?Usage: ./compare.sh <suite> <left-variant> <right-variant>}"

SKIP_RUN="${SKIP_RUN:-false}"

LEFT_ROOT="./build/${SUITE}/${LEFT_VARIANT}"
RIGHT_ROOT="./build/${SUITE}/${RIGHT_VARIANT}"

for BENCH_DIR in "${LEFT_ROOT}"/*; do
    [[ -d "$BENCH_DIR" ]] || continue

    BENCHMARK=$(basename "$BENCH_DIR")

    LEFT_BINARY="${LEFT_ROOT}/${BENCHMARK}/${BENCHMARK}"
    RIGHT_BINARY="${RIGHT_ROOT}/${BENCHMARK}/${BENCHMARK}"

    [[ -x "$LEFT_BINARY" ]] || { echo "Skipping ${BENCHMARK}: missing ${LEFT_BINARY}"; continue; }
    [[ -x "$RIGHT_BINARY" ]] || { echo "Skipping ${BENCHMARK}: missing ${RIGHT_BINARY}"; continue; }

    if [[ "$SKIP_RUN" == false ]]; then
        echo -n "Validating ${BENCHMARK}: ${LEFT_VARIANT} vs ${RIGHT_VARIANT}... "

        if [[ "$SUITE" == "polybench" ]]; then
            LEFT_OUT="${BENCH_DIR}/${BENCHMARK}-${LEFT_VARIANT}_out.txt"
            RIGHT_OUT="${RIGHT_ROOT}/${BENCHMARK}/${BENCHMARK}-${RIGHT_VARIANT}_out.txt"

            "$LEFT_BINARY" 2>&1 | sed -n '/==BEGIN/,/==END/p' > "$LEFT_OUT"
            "$RIGHT_BINARY" 2>&1 | sed -n '/==BEGIN/,/==END/p' > "$RIGHT_OUT"

            diff "$LEFT_OUT" "$RIGHT_OUT" > /dev/null 2>&1 && echo "PASS" || echo "FAIL"
        else
            if "$LEFT_BINARY" > /dev/null 2>&1 && "$RIGHT_BINARY" > /dev/null 2>&1; then
                echo "PASS"
            else
                echo "FAIL"
            fi
        fi
    fi

    echo "Benchmarking ${BENCHMARK}: ${LEFT_VARIANT} vs ${RIGHT_VARIANT}"

    taskset -c 0,3 hyperfine \
        --prepare=true \
        --warmup 3 \
        --runs 20 \
        --shell=none \
        --ignore-failure \
        "$LEFT_BINARY" \
        "$RIGHT_BINARY"

    echo
done