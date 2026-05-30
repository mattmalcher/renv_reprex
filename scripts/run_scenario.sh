#!/usr/bin/env bash
# Container entrypoint: run_scenario.sh <SCENARIO>
set -euo pipefail

SCENARIO="${1:-${SCENARIO:-unknown}}"
export SCENARIO

# Two-phase scenarios (4, 6-9) pass PHASE=install or PHASE=snapshot from the host.
# Scenario 5 and discovery scenarios (1-3) run single-phase and ignore PHASE.
PHASE="${PHASE:-}"

OUT="/artifacts/${SCENARIO}"
mkdir -p "$OUT"
PROJ="/project"

log() { echo "[run_scenario ${SCENARIO}] $*"; }

run_r() {
  local script="$1"
  local label
  label="$(basename "$script" .R)"
  log "Running ${label}..."
  timeout 300 Rscript --no-save --no-restore "$script" 2>&1 | tee "${OUT}/${label}.log" || {
    local rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 124 ]; then
      echo "TIMEOUT" > "${OUT}/${label}.status"
    else
      echo "ERROR:${rc}" > "${OUT}/${label}.status"
    fi
    log "Script ${label} exited with status ${rc}"
    return "$rc"
  }
  echo "OK" > "${OUT}/${label}.status"
}

run_r_noenv() {
  local script="$1"
  local label
  label="$(basename "$script" .R)"
  log "Running ${label} (no-init-file)..."
  timeout 300 Rscript --no-save --no-restore --no-init-file "$script" 2>&1 | tee "${OUT}/${label}.log" || {
    local rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 124 ]; then
      echo "TIMEOUT" > "${OUT}/${label}.status"
    else
      echo "ERROR:${rc}" > "${OUT}/${label}.status"
    fi
    log "Script ${label} exited with status ${rc}"
    return "$rc"
  }
  echo "OK" > "${OUT}/${label}.status"
}

setup_rprofile() {
  local tpl="/templates/scenario_${SCENARIO}.Rprofile"
  if [ -f "$tpl" ]; then
    cp "$tpl" "${PROJ}/.Rprofile"
    log "Installed .Rprofile from $tpl"
  else
    log "No .Rprofile template for scenario ${SCENARIO} — renv::init() will create one"
  fi
}

cd "$PROJ"

case "$SCENARIO" in

  REPORT)
    exec Rscript --no-save --no-restore --no-init-file /scripts/70_collect_artifacts.R
    ;;

  1)
    # Dependency discovery without biocViews — baseline, no snapshot
    run_r /scripts/00_env_diagnostics.R
    export FIXTURE=cranlike-no-biocviews
    run_r /scripts/01_discover_deps.R
    run_r_noenv /scripts/70_collect_artifacts.R
    ;;

  2)
    # Dependency discovery with non-empty biocViews — proves the crux
    run_r /scripts/00_env_diagnostics.R
    export FIXTURE=cranlike-with-biocviews
    run_r /scripts/01_discover_deps.R
    run_r_noenv /scripts/70_collect_artifacts.R
    ;;

  3)
    # Real-world trigger: recipes is CRAN-installed but has non-empty biocViews
    run_r /scripts/00_env_diagnostics.R
    run_r /scripts/03_inspect_recipes.R
    run_r_noenv /scripts/70_collect_artifacts.R
    ;;

  4)
    # Snapshot failure: metaRNASeq (biocViews present), Bioc blocked.
    # Two-phase: install via renv with open network; snapshot with Bioc blocked.
    if [ "$PHASE" = "install" ]; then
      setup_rprofile
      export PACKAGE=metaRNASeq
      run_r /scripts/10_init_project.R
      run_r /scripts/20_install_pkg.R
    elif [ "$PHASE" = "snapshot" ]; then
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
    ;;

  5)
    # Snapshot control: glue (no biocViews), Bioc blocked throughout — should succeed.
    # Single-phase: renv::install(glue) works fine even with Bioc blocked (no biocViews).
    setup_rprofile
    run_r /scripts/00_env_diagnostics.R
    run_r /scripts/10_init_project.R
    export PACKAGE=glue
    run_r /scripts/20_install_pkg.R
    run_r /scripts/30_snapshot.R || true
    run_r_noenv /scripts/70_collect_artifacts.R
    ;;

  6)
    # Workaround: renv::settings$bioconductor.version("3.20")
    # bioconductor.version is set in 10_init_project.R when SCENARIO=6
    if [ "$PHASE" = "install" ]; then
      setup_rprofile
      export PACKAGE=metaRNASeq
      run_r /scripts/10_init_project.R
      run_r /scripts/20_install_pkg.R
    elif [ "$PHASE" = "snapshot" ]; then
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
    ;;

  7)
    # Workaround: BiocVersion available via PPM Bioconductor mirror
    # bioconductor.org blocked; PPM BioCsoft repo is reachable
    if [ "$PHASE" = "install" ]; then
      setup_rprofile
      export PACKAGE=metaRNASeq
      run_r /scripts/10_init_project.R
      run_r /scripts/20_install_pkg.R
    elif [ "$PHASE" = "snapshot" ]; then
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
    ;;

  8)
    # Workaround: stub renv.bioconductor.repos pointing at PPM root
    if [ "$PHASE" = "install" ]; then
      setup_rprofile
      export PACKAGE=metaRNASeq
      run_r /scripts/10_init_project.R
      run_r /scripts/20_install_pkg.R
    elif [ "$PHASE" = "snapshot" ]; then
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
    ;;

  9)
    # Workaround: renv.bioconductor.repos pointing at CRAN PPM URL
    if [ "$PHASE" = "install" ]; then
      setup_rprofile
      export PACKAGE=metaRNASeq
      run_r /scripts/10_init_project.R
      run_r /scripts/20_install_pkg.R
    elif [ "$PHASE" = "snapshot" ]; then
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
    ;;

  *)
    log "Unknown scenario: ${SCENARIO}"
    exit 1
    ;;
esac

log "Done."
