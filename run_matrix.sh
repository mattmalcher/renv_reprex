#!/usr/bin/env bash
# run_matrix.sh — build the renv/Bioconductor debugging harness image and run all scenarios.
#
# Usage:
#   ./run_matrix.sh              # run all scenarios
#   ./run_matrix.sh A B          # run specific scenarios
#   ./run_matrix.sh --build-only # build image and exit
#
# Prerequisites:
#   - Docker installed (sudo docker works, or the current user is in the docker group)
#   - Internet access for PPM

set -euo pipefail

IMAGE="renv-debug"
ARTIFACTS="$(cd "$(dirname "$0")" && pwd)/artifacts"
TIMEOUT=300  # 5 min per scenario

# Detect docker invocation (group membership vs sudo)
if docker info &>/dev/null 2>&1; then
  DOCKER="docker"
elif sudo docker info &>/dev/null 2>&1; then
  DOCKER="sudo docker"
else
  echo "ERROR: cannot reach Docker daemon. Is Docker installed and running?" >&2
  exit 1
fi

BLOCK_HOSTS=(
  "--add-host" "bioconductor.org:127.0.0.1"
  "--add-host" "www.bioconductor.org:127.0.0.1"
  "--add-host" "bioconductor.statistik.tu-dortmund.de:127.0.0.1"
  "--add-host" "master.bioconductor.org:127.0.0.1"
)

build_image() {
  echo "=== Building image: ${IMAGE} ==="
  $DOCKER build -t "$IMAGE" "$(dirname "$0")"
  echo "=== Build complete ==="
}

run_scenario() {
  local name="$1"; shift
  local extra_args=("$@")
  local log_dir="${ARTIFACTS}/${name}"
  mkdir -p "$log_dir"

  echo ""
  echo "━━━ Scenario ${name} ━━━"
  $DOCKER run --rm \
    -v "${ARTIFACTS}:/artifacts" \
    -e SCENARIO="$name" \
    "${extra_args[@]}" \
    "$IMAGE" "$name" \
    2>&1 | tee "${log_dir}/run.log" &
  local pid=$!

  # Enforce timeout
  (sleep $TIMEOUT && kill $pid 2>/dev/null && \
    echo "TIMEOUT: Scenario ${name} exceeded ${TIMEOUT}s" >> "${log_dir}/run.log") &
  local watchdog=$!

  if wait $pid 2>/dev/null; then
    kill $watchdog 2>/dev/null || true
    echo "Scenario ${name}: completed"
  else
    kill $watchdog 2>/dev/null || true
    echo "Scenario ${name}: FAILED or TIMED OUT (see ${log_dir}/run.log)"
    echo "TIMEOUT_OR_FAILURE" > "${log_dir}/scenario_status.txt"
  fi
}

# ── parse args ─────────────────────────────────────────────────────────────────

ALL_SCENARIOS=(A B C D E F G H)
RUN_SCENARIOS=()
BUILD_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=true ;;
    [A-H])        RUN_SCENARIOS+=("$arg") ;;
    *)            echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [ ${#RUN_SCENARIOS[@]} -eq 0 ]; then
  RUN_SCENARIOS=("${ALL_SCENARIOS[@]}")
fi

mkdir -p "$ARTIFACTS"
build_image

if $BUILD_ONLY; then
  echo "Build-only mode — exiting."
  exit 0
fi

# ── run scenarios ──────────────────────────────────────────────────────────────

# Scenarios B–H depend on A's lockfile. Ensure A runs first.
if [[ ! -f "${ARTIFACTS}/A/renv.lock" ]]; then
  echo "Running Scenario A first (required baseline for B–H)..."
  run_scenario A
fi

for s in "${RUN_SCENARIOS[@]}"; do
  case "$s" in
    A)
      if [[ -f "${ARTIFACTS}/A/renv.lock" ]]; then
        echo "Scenario A already complete — skipping."
      else
        run_scenario A
      fi
      ;;
    B)
      run_scenario B "${BLOCK_HOSTS[@]}"
      ;;
    C)
      run_scenario C "${BLOCK_HOSTS[@]}"
      ;;
    D)
      run_scenario D "${BLOCK_HOSTS[@]}" -e R_BIOC_VERSION=3.20
      ;;
    E)
      run_scenario E "${BLOCK_HOSTS[@]}"
      ;;
    F)
      run_scenario F "${BLOCK_HOSTS[@]}"
      ;;
    G)
      run_scenario G "${BLOCK_HOSTS[@]}"
      ;;
    H)
      run_scenario H "${BLOCK_HOSTS[@]}"
      ;;
  esac
done

# ── generate cross-scenario report ────────────────────────────────────────────

echo ""
echo "━━━ Generating cross-scenario report ━━━"
$DOCKER run --rm \
  -v "${ARTIFACTS}:/artifacts" \
  -e SCENARIO=REPORT \
  "$IMAGE" REPORT \
  2>&1 | tee "${ARTIFACTS}/report_generation.log"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Done. Artifacts in: ${ARTIFACTS}/"
echo ""
echo "  summary.json  → machine-readable results"
echo "  report.md     → Posit Support report"
echo ""
ls -lh "${ARTIFACTS}/"
