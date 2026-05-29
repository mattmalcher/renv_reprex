#!/usr/bin/env bash
# Container entrypoint: run_scenario.sh <SCENARIO>
set -euo pipefail

SCENARIO="${1:-${SCENARIO:-unknown}}"
export SCENARIO

OUT="/artifacts/${SCENARIO}"
mkdir -p "$OUT"
PROJ="/project"

log() { echo "[run_scenario ${SCENARIO}] $*"; }

# Helper: run an R script in /project (reads site Rprofile + project .Rprofile).
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

# Helper: run an R script skipping the project .Rprofile (for artifact/reporting
# scripts that don't need renv active and must not fail due to BiocManager issues).
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

# ── scenario-specific setup ──────────────────────────────────────────────────

setup_rprofile() {
  # Copy scenario template if it exists. If no template, leave .Rprofile absent
  # so renv::init() can create it with the activation stanza itself.
  local tpl="/templates/scenario_${SCENARIO}.Rprofile"
  if [ -f "$tpl" ]; then
    cp "$tpl" "${PROJ}/.Rprofile"
    log "Installed .Rprofile from $tpl"
  else
    log "No .Rprofile template for scenario ${SCENARIO} — renv::init() will create one"
  fi
}

setup_renviron() {
  local tpl="/templates/scenario_${SCENARIO}.Renviron"
  if [ -f "$tpl" ]; then
    cp "$tpl" "${PROJ}/.Renviron"
    log "Installed .Renviron from $tpl"
  fi
}

cd "$PROJ"

case "$SCENARIO" in

  REPORT)
    # Cross-scenario summary — no R project needed
    exec Rscript --no-save --no-restore --no-init-file /scripts/70_collect_artifacts.R
    ;;

  A)
    # Scenario A: open network, baseline that should succeed.
    # BiocVersion is installed explicitly (Bioc is reachable) to satisfy renv's
    # pre-flight check before snapshot.
    setup_rprofile
    setup_renviron
    run_r /scripts/00_env_diagnostics.R
    run_r /scripts/10_init_project.R
    run_r /scripts/20_install_trigger_pkg.R
    run_r /scripts/25_install_biocversion.R
    run_r /scripts/30_snapshot.R       || true
    run_r /scripts/60_startup_check.R  || true
    run_r /scripts/50_restore.R        || true
    run_r_noenv /scripts/70_collect_artifacts.R
    ;;

  H)
    # Scenario H: manual lockfile patch approach.
    # Uses snapshot(check=FALSE) to bypass the BiocVersion preflight and produce a
    # lockfile, patches out Bioc refs, then tests which renv operation re-adds them.
    setup_rprofile
    setup_renviron
    run_r /scripts/00_env_diagnostics.R
    run_r /scripts/10_init_project.R
    run_r /scripts/20_install_trigger_pkg.R

    # Generate lockfile bypassing BiocVersion preflight check
    run_r /scripts/31_snapshot_force.R

    [ -f "${PROJ}/renv.lock" ] && cp "${PROJ}/renv.lock" "${OUT}/H_pre_patch_lockfile.json"

    # Patch out Bioconductor references (run without project .Rprofile)
    run_r_noenv /scripts/40_patch_lockfile.R
    [ -f "${PROJ}/renv.lock" ] && cp "${PROJ}/renv.lock" "${OUT}/H_patched_lockfile.json"

    # ── sub-test: startup ───────────────────────────────────────────────────
    log "--- H: sub-test startup ---"
    cp "${OUT}/H_patched_lockfile.json" "${PROJ}/renv.lock"
    SUBTEST=startup run_r /scripts/60_startup_check.R || true
    [ -f "${PROJ}/renv.lock" ] && cp "${PROJ}/renv.lock" "${OUT}/H_after_startup_lockfile.json"

    # ── sub-test: snapshot ──────────────────────────────────────────────────
    log "--- H: sub-test snapshot ---"
    cp "${OUT}/H_patched_lockfile.json" "${PROJ}/renv.lock"
    SUBTEST=snapshot run_r /scripts/30_snapshot.R || true
    [ -f "${PROJ}/renv.lock" ] && cp "${PROJ}/renv.lock" "${OUT}/H_after_snapshot_lockfile.json"

    # ── sub-test: restore ───────────────────────────────────────────────────
    log "--- H: sub-test restore ---"
    cp "${OUT}/H_patched_lockfile.json" "${PROJ}/renv.lock"
    SUBTEST=restore run_r /scripts/50_restore.R || true
    [ -f "${PROJ}/renv.lock" ] && cp "${PROJ}/renv.lock" "${OUT}/H_after_restore_lockfile.json"

    run_r_noenv /scripts/70_collect_artifacts.R
    ;;

  *)
    # Scenarios B–G: Bioconductor blocked, PPM reachable.
    # Each scenario runs its own full workflow — no lockfile substitution.
    # The workaround (if any) is applied via the scenario's .Rprofile/.Renviron template.
    setup_rprofile
    setup_renviron
    run_r /scripts/00_env_diagnostics.R
    run_r /scripts/10_init_project.R
    run_r /scripts/20_install_trigger_pkg.R
    run_r /scripts/30_snapshot.R      || true
    run_r /scripts/60_startup_check.R || true
    run_r /scripts/50_restore.R       || true
    run_r_noenv /scripts/70_collect_artifacts.R
    ;;
esac

log "Done."
