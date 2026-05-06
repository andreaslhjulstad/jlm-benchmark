#!/usr/bin/env bash
#SBATCH --partition=CPUQ
#SBATCH --account=share-ie-idi
#SBATCH --job-name=jlm-build
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=20G
#SBATCH --time=48:00:00
#SBATCH --array=0-14
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

TASKS_PER_ARRAY_JOB=16
OFFSET=$((SLURM_ARRAY_TASK_ID * TASKS_PER_ARRAY_JOB))

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

for SUITE in "${SUITES[@]}"; do
    case "$SUITE" in
        polybench)
            FILTER="polybench"
            ;;
        embench)
            FILTER="embench"
            ;;
        *)
            echo "Unknown suite: $SUITE"
            exit 1
            ;;
    esac

    for VARIANT in "${VARIANTS[@]}"; do
        echo "Building suite=${SUITE}, variant=${VARIANT}, offset=${OFFSET}"

        EXTRA_ARGS=()

        if [[ "$VARIANT" != "clang-o3" ]]; then
            EXTRA_ARGS+=(--useMem2reg)
        fi

        ./benchmark.py \
            --llvmbin "$LLVM_BIN" \
            --jlm-opt "$JLM_OPT" \
            --sources "$SOURCES_JSON" \
            --filter "$FILTER" \
            --variant "$VARIANT" \
            --regionAwareModRef \
            --builddir "build/${SUITE}/${VARIANT}" \
            --statsdir "statistics/${SUITE}/${VARIANT}" \
            --offset "$OFFSET" \
            --limit "$TASKS_PER_ARRAY_JOB" \
            -j 16 \
            "${EXTRA_ARGS[@]}"
    done
done
