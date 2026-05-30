#!/usr/bin/env bash
# Container entrypoint: run_scenario.sh <SCENARIO>
set -euo pipefail

SCENARIO="${1:-${SCENARIO:-unknown}}"
export SCENARIO

# Two-phase scenarios (4, 6, 7) pass PHASE=install or PHASE=snapshot from the host.
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
  timeout 300 Rscript --no-save --no-restore \
    -e "source('${script}', echo=TRUE, max.deparse.length=Inf)" || {
    local rc=$?
    log "Script ${label} exited with status ${rc}"
    return "$rc"
  }
}

run_r_noenv() {
  local script="$1"
  local label
  label="$(basename "$script" .R)"
  log "Running ${label} (no-init-file)..."
  timeout 300 Rscript --no-save --no-restore --no-init-file \
    -e "source('${script}', echo=TRUE, max.deparse.length=Inf)" || {
    local rc=$?
    log "Script ${label} exited with status ${rc}"
    return "$rc"
  }
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
    # Path B — snapshot failure: project depends on metaRNASeq (a CRAN/PPM package
    # whose DESCRIPTION carries biocViews). BiocVersion is NOT discovered as a
    # dependency; snapshot fails when renv infers Source="Bioconductor" from the
    # installed DESCRIPTION and tries to validate the Bioconductor version.
    # Two-phase: install via renv with open network; snapshot with Bioc blocked.
    if [ "$PHASE" = "install" ]; then
      setup_rprofile
      export PACKAGE=metaRNASeq
      run_r /scripts/10_init_project.R
      run_r /scripts/20_install_pkg.R
    elif [ "$PHASE" = "snapshot" ]; then
      export PACKAGE=metaRNASeq
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
    ;;

  5)
    # Minimal-pair control for scenario 4: identical package (metaRNASeq), source
    # (PPM/RSPM), and two-phase blocked network — the ONLY difference is that the
    # biocViews field is stripped from the installed DESCRIPTION before snapshot.
    # With biocViews gone, snapshot succeeds and records metaRNASeq.
    if [ "$PHASE" = "install" ]; then
      setup_rprofile
      export PACKAGE=metaRNASeq
      run_r /scripts/10_init_project.R
      run_r /scripts/20_install_pkg.R
    elif [ "$PHASE" = "snapshot" ]; then
      export PACKAGE=metaRNASeq
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/40_strip_biocviews.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
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
      export PACKAGE=metaRNASeq
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
      export PACKAGE=metaRNASeq
      run_r /scripts/00_env_diagnostics.R
      run_r /scripts/30_snapshot.R || true
      run_r_noenv /scripts/70_collect_artifacts.R
    fi
    ;;

  8)
    # Path A — the project ITSELF is a package with a non-empty biocViews field.
    # renv::dependencies() genuinely discovers BiocManager + BiocVersion as implicit
    # dependencies; installing the project's declared dependencies then FAILS because
    # BiocVersion (Bioconductor-only) cannot be downloaded with Bioconductor blocked.
    # Single-phase (no external package install needed beforehand).
    run_r /scripts/00_env_diagnostics.R
    export FIXTURE=cranlike-with-biocviews
    run_r /scripts/15_setup_pkg_project.R
    run_r /scripts/16_install_project_deps.R || true
    run_r_noenv /scripts/70_collect_artifacts.R
    ;;


  *)
    log "Unknown scenario: ${SCENARIO}"
    exit 1
    ;;
esac

log "Done."
