#!/usr/bin/env bash
# run_matrix.sh — build the renv biocViews/BiocVersion debugging harness and run scenarios.
#
# Usage:
#   ./run_matrix.sh              # run all 8 scenarios
#   ./run_matrix.sh 2 4 5        # run specific scenarios
#   ./run_matrix.sh --build-only # build image and exit
#
# Prerequisites:
#   - Docker installed (sudo docker works, or current user is in the docker group)
#   - Internet access for Posit Package Manager (packagemanager.posit.co)

set -euo pipefail

IMAGE="renv-biocviews-debug"
ARTIFACTS="$(cd "$(dirname "$0")" && pwd)/artifacts"
TIMEOUT=300  # 5 min per scenario

PPM_BIOC_URL="https://packagemanager.posit.co/bioconductor/__linux__/noble/latest"

if docker info &>/dev/null 2>&1; then
  DOCKER="docker"
elif sudo docker info &>/dev/null 2>&1; then
  DOCKER="sudo docker"
else
  echo "ERROR: cannot reach Docker daemon. Is Docker installed and running?" >&2
  exit 1
fi

# Hosts to block to simulate an enterprise environment where bioconductor.org is unreachable
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

# Run one `docker …` invocation under a timeout watchdog, teeing to a log file.
#   run_with_watchdog <log_file> <append:0|1> -- <docker args…>
# Returns the container's exit status (or non-zero if the watchdog killed it).
run_with_watchdog() {
  local log_file="$1"; local append="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  local tee_flag=(); [ "$append" = "1" ] && tee_flag=(-a)

  $DOCKER "$@" > >(tee "${tee_flag[@]}" "$log_file") 2>&1 &
  local pid=$!
  (sleep $TIMEOUT && kill $pid 2>/dev/null && \
    echo "TIMEOUT: exceeded ${TIMEOUT}s" >> "$log_file") &
  local watchdog=$!
  local rc=0
  wait $pid 2>/dev/null || rc=$?
  kill $watchdog 2>/dev/null || true
  return $rc
}

# Delete a (possibly root-owned) host directory's contents via a throwaway container.
clean_project_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  $DOCKER run --rm -v "${dir}:/toclean" --entrypoint sh "$IMAGE" \
    -c "find /toclean -mindepth 1 -delete" 2>/dev/null || true
}

# Single-phase run: entire scenario in one container with the given docker args.
run_scenario() {
  local name="$1"; shift
  local extra_args=("$@")
  local log_dir="${ARTIFACTS}/${name}"
  mkdir -p "$log_dir"

  echo ""
  echo "━━━ Scenario ${name} ━━━"

  if run_with_watchdog "${log_dir}/output.log" 0 -- \
      run --rm -v "${ARTIFACTS}:/artifacts" -e SCENARIO="$name" \
      "${extra_args[@]}" "$IMAGE" "$name"; then
    echo "Scenario ${name}: completed"
  else
    echo "Scenario ${name}: FAILED or TIMED OUT (see ${log_dir}/output.log)"
  fi
}

# Two-phase run: install phase (open network) then snapshot phase (blocked network).
# /project is mounted from the host so the renv library persists between phases.
# snapshot_args are passed only to the snapshot container (blocking, extra -e flags, etc.)
run_two_phase_scenario() {
  local name="$1"; shift
  local snapshot_args=("$@")
  local log_dir="${ARTIFACTS}/${name}"
  local project_dir="${log_dir}/_project"

  mkdir -p "$log_dir"
  echo ""
  echo "━━━ Scenario ${name} ━━━"

  clean_project_dir "$project_dir"   # clear any stale (root-owned) state from a prior run
  mkdir -p "$project_dir"

  # ── Phase 1: install (open network) ────────────────────────────────────────
  run_with_watchdog "${log_dir}/output.log" 0 -- \
    run --rm -v "${ARTIFACTS}:/artifacts" -v "${project_dir}:/project" \
    -e SCENARIO="$name" -e PHASE=install "$IMAGE" "$name" || true

  # ── Phase 2: snapshot (blocked network) ────────────────────────────────────
  if run_with_watchdog "${log_dir}/output.log" 1 -- \
      run --rm -v "${ARTIFACTS}:/artifacts" -v "${project_dir}:/project" \
      -e SCENARIO="$name" -e PHASE=snapshot "${snapshot_args[@]}" "$IMAGE" "$name"; then
    echo "Scenario ${name}: completed"
  else
    echo "Scenario ${name}: FAILED or TIMED OUT (see ${log_dir}/output.log)"
  fi

  clean_project_dir "$project_dir"
  rmdir "$project_dir" 2>/dev/null || true
}

# ── parse args ─────────────────────────────────────────────────────────────────

ALL_SCENARIOS=(1 2 3 4 5 6 7 8)
RUN_SCENARIOS=()
BUILD_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=true ;;
    [1-8])        RUN_SCENARIOS+=("$arg") ;;
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

for s in "${RUN_SCENARIOS[@]}"; do
  case "$s" in
    1)
      # Dependency discovery — no biocViews; no network blocking needed
      run_scenario 1
      ;;
    2)
      # Dependency discovery — with biocViews; no network blocking needed
      run_scenario 2
      ;;
    3)
      # Real-world package inspection (genetics); network open to install from PPM
      run_scenario 3
      ;;
    4)
      # Path B — snapshot failure: metaRNASeq (biocViews present), Bioc blocked
      # Two-phase: install open network; snapshot with Bioc blocked
      run_two_phase_scenario 4 "${BLOCK_HOSTS[@]}"
      ;;
    5)
      # Minimal-pair control: metaRNASeq with biocViews stripped, Bioc blocked
      # Two-phase, identical to scenario 4 except the biocViews field is removed
      run_two_phase_scenario 5 "${BLOCK_HOSTS[@]}"
      ;;
    6)
      # Workaround: bioconductor.version("3.20"), Bioc blocked
      run_two_phase_scenario 6 "${BLOCK_HOSTS[@]}"
      ;;
    7)
      # Workaround: PPM Bioconductor mirror as BioCsoft repo, Bioc blocked
      run_two_phase_scenario 7 "${BLOCK_HOSTS[@]}" -e PPM_BIOC_URL="${PPM_BIOC_URL}"
      ;;
    8)
      # Path A: project IS a package with biocViews; BiocVersion discovered, Bioc blocked
      # Single-phase: no external package install needed
      run_scenario 8 "${BLOCK_HOSTS[@]}"
      ;;
  esac
done

# ── generate summary.json ─────────────────────────────────────────────────────

echo ""
echo "━━━ Generating summary.json ━━━"
$DOCKER run --rm \
  -v "${ARTIFACTS}:/artifacts" \
  --entrypoint Rscript \
  "$IMAGE" \
  --no-save --no-restore -e "
    library(jsonlite)
    ss <- as.character(1:8)
    results <- lapply(setNames(ss, ss), function(s) {
      p <- file.path('/artifacts', s, 'result.json')
      if (file.exists(p)) fromJSON(p, simplifyVector = FALSE)
      else list(scenario = s, notes = 'not run')
    })
    # null='null' so a JSON null read back as R NULL is re-emitted as null,
    # not as the empty object '{}' that toJSON produces for NULL by default.
    writeLines(toJSON(results, auto_unbox = TRUE, pretty = TRUE, na = 'null', null = 'null'),
               '/artifacts/summary.json')
    cat('Wrote summary.json\n')
  "

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Done. Artifacts in: ${ARTIFACTS}/"
echo ""
echo "  summary.json           → machine-readable results for all scenarios"
echo "  <N>/result.json        → per-scenario structured outcome"
echo "  <N>/discovered-dependencies.csv  → dependency discovery results"
echo "  <N>/output.log         → full container output"
echo ""
ls -lh "${ARTIFACTS}/"
