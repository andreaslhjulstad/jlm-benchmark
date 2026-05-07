#!/usr/bin/env bash
#SBATCH --partition=CPUQ
#SBATCH --account=share-ie-idi
#SBATCH --job-name=jlm-build
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=20G
#SBATCH --time=48:00:00
#SBATCH -o slurm-log/build.%A.%a.out

set -euo pipefail

SELF=./run-slurm.sh

if [ -z "${APPTAINER_NAME+x}" ]; then
    exec apptainer exec "$APPTAINER_CONTAINER" "$SELF" "$@"
fi

JLM_PATH="jlm"
SOURCES_JSON="${SOURCES_JSON:-sources/sources.json}"

if [ -f .env ]; then
    source .env
fi

LLVM_BIN="$(llvm-config-18 --bindir)"
JLM_OPT="${JLM_OPT:-${JLM_PATH}/build-release/jlm-opt}"

SUITES=(
    "polybench"
    "embench"
)

VARIANTS=(
    "lsr"
    "no-lsr"
    "m2r"
    "clang-o3"
)

mkdir -p build statistics slurm-log

JOBS=()

for SUITE in "${SUITES[@]}"; do
    case "$SUITE" in
        polybench)
            SUITE_FILTER="polybench"
            ;;
        embench)
            SUITE_FILTER="embench"
            ;;
        *)
            echo "Unknown suite: $SUITE"
            exit 1
            ;;
    esac

    mapfile -t BENCHMARKS < <(
        ./benchmark.py \
            --llvmbin "$LLVM_BIN" \
            --jlm-opt "$JLM_OPT" \
            --sources "$SOURCES_JSON" \
            --filter "$SUITE_FILTER" \
            --list \
        | awk '/^  / { print $1 }'
    )

    for BENCHMARK in "${BENCHMARKS[@]}"; do
        JOBS+=("${SUITE}:${BENCHMARK}")
    done
done

if [[ "${#JOBS[@]}" -eq 0 ]]; then
    echo "No benchmarks found."
    exit 1
fi

if [[ "$SLURM_ARRAY_TASK_ID" -ge "${#JOBS[@]}" ]]; then
    echo "Array task ${SLURM_ARRAY_TASK_ID} out of range. Jobs: ${#JOBS[@]}"
    exit 0
fi

ENTRY="${JOBS[$SLURM_ARRAY_TASK_ID]}"
SUITE="${ENTRY%%:*}"
BENCHMARK="${ENTRY#*:}"

echo "Building complete benchmark:"
echo "  Suite:     ${SUITE}"
echo "  Benchmark: ${BENCHMARK}"

for VARIANT in "${VARIANTS[@]}"; do
    echo "Building suite=${SUITE}, benchmark=${BENCHMARK}, variant=${VARIANT}"

    EXTRA_ARGS=()

    if [[ "$VARIANT" != "clang-o3" ]]; then
        EXTRA_ARGS+=(--useMem2reg)
    fi

    ./benchmark.py \
        --llvmbin "$LLVM_BIN" \
        --jlm-opt "$JLM_OPT" \
        --sources "$SOURCES_JSON" \
        --filter "^${BENCHMARK}$" \
        --variant "$VARIANT" \
        --regionAwareModRef \
        --builddir "build/${SUITE}/${VARIANT}" \
        --statsdir "statistics/${SUITE}/${VARIANT}" \
        -j 16 \
        "${EXTRA_ARGS[@]}"
done
