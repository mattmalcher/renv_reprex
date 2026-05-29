source("/scripts/bioc_detect.R")
`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

scenario <- Sys.getenv("SCENARIO", "unknown")
cat("=== 70_collect_artifacts ===\n")
cat("Scenario:", scenario, "\n\n")

artifacts_root <- "/artifacts"

# ── per-scenario artifact consolidation ───────────────────────────────────────

if (scenario != "REPORT") {
  out_dir <- file.path(artifacts_root, scenario)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # Copy key files if they exist in /project
  for (f in c("renv.lock", "renv/settings.json")) {
    if (file.exists(f)) {
      dest <- file.path(out_dir, basename(f))
      file.copy(f, dest, overwrite = TRUE)
      cat("Saved", f, "→", dest, "\n")
    }
  }

  # ── classify scenario outcome ────────────────────────────────────────────────

  read_json_safe <- function(path) {
    tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
  }

  env   <- read_json_safe(file.path(out_dir, "env_diagnostics.json"))
  snap  <- read_json_safe(file.path(out_dir, "snapshot_result.json"))
  rest  <- read_json_safe(file.path(out_dir, "restore_result.json"))
  start <- read_json_safe(file.path(out_dir, "startup_result.json"))

  classify_status <- function(result_str) {
    if (is.null(result_str)) return("unknown")
    if (result_str == "success") return("success")
    if (grepl("^error", result_str)) return("failure")
    if (grepl("timeout", result_str, ignore.case = TRUE)) return("timeout")
    result_str
  }

  lock_path     <- file.path(out_dir, "renv.lock")
  settings_path <- file.path(out_dir, "settings.json")

  settings_obj  <- if (file.exists(settings_path))
    tryCatch(jsonlite::fromJSON(settings_path, simplifyVector = FALSE), error = function(e) list())
  else list()

  # For scenario H: determine which sub-test re-introduced Bioc refs
  reintroduced_by <- NA_character_
  if (scenario == "H") {
    startup_after <- read_json_safe(file.path(out_dir, "startup_result.json"))
    snap_after    <- read_json_safe(file.path(out_dir, "snapshot_result.json"))
    rest_after    <- read_json_safe(file.path(out_dir, "restore_result.json"))
    reintro_parts <- character(0)
    if (isTRUE(startup_after$bioc_refs)) reintro_parts <- c(reintro_parts, "startup")
    if (isTRUE(snap_after$bioc_refs))    reintro_parts <- c(reintro_parts, "snapshot")
    if (isTRUE(rest_after$bioc_refs))    reintro_parts <- c(reintro_parts, "restore")
    reintroduced_by <- if (length(reintro_parts) > 0) paste(reintro_parts, collapse = "+") else "none"
  }

  key_error <- NA_character_
  for (log_f in list.files(out_dir, pattern = "\\.log$", full.names = TRUE)) {
    log_lines <- readLines(log_f, warn = FALSE)
    err_lines <- grep("^(Error|ERROR|WARNING|TIMEOUT)", log_lines, value = TRUE)
    if (length(err_lines) > 0) {
      key_error <- err_lines[[1]]
      break
    }
  }

  result <- list(
    scenario_name            = scenario,
    ppm_access               = isTRUE(env$ppm_access),
    bioc_access              = isTRUE(env$bioc_access),
    lockfile_has_bioc_refs   = lockfile_has_bioc_refs(lock_path),
    settings_has_bioc_version = !is.null(settings_obj$`bioconductor.version`),
    startup_status           = classify_status(start$result),
    snapshot_status          = classify_status(snap$result),
    restore_status           = classify_status(rest$result),
    lockfile_reintroduced_by = reintroduced_by,
    key_error_message        = key_error %||% NA_character_
  )

  writeLines(
    jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(out_dir, "scenario_result.json")
  )
  cat("Wrote scenario_result.json\n")
  cat("\nOutcome summary:\n")
  cat(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"), "\n")

} else {
  # ── REPORT mode: cross-scenario aggregation ──────────────────────────────────

  scenarios <- c("A", "B", "C", "D", "E", "F", "G", "H")
  results   <- list()

  read_json_safe <- function(path) {
    tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
  }

  for (s in scenarios) {
    r_path <- file.path(artifacts_root, s, "scenario_result.json")
    if (file.exists(r_path)) {
      results[[s]] <- read_json_safe(r_path)
    } else {
      results[[s]] <- list(scenario_name = s, note = "not run")
    }
  }

  # summary.json
  writeLines(
    jsonlite::toJSON(results, auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(artifacts_root, "summary.json")
  )
  cat("Wrote artifacts/summary.json\n")

  # report.md
  env_A <- read_json_safe(file.path(artifacts_root, "A", "env_diagnostics.json"))

  report_lines <- c(
    "# renv / Bioconductor Failure Mode Report",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")),
    "",
    "---",
    "",
    "## Environment",
    "",
    paste0("- **R version**: ", env_A$r_version %||% "unknown"),
    paste0("- **renv version**: ", env_A$renv_version %||% "unknown"),
    paste0("- **OS**: Ubuntu 24.04 (Noble), Docker container"),
    paste0("- **PPM URL**: ", if (is.character(env_A$repos)) env_A$repos[[1]] else env_A$repos[["CRAN"]] %||% "unknown"),
    paste0("- **Trigger package**: recipes"),
    paste0("- **Bioconductor version tested**: 3.20"),
    "",
    "---",
    "",
    "## Scenario Results",
    "",
    "| Scenario | Bioc blocked | PPM ok | Bioc refs in lock | Startup | Snapshot | Restore | Re-introduced by |",
    "|---|---|---|---|---|---|---|---|"
  )

  scenario_desc <- c(
    A = "Control (open network)",
    B = "Blocked, default config",
    C = "Blocked + renv.bioconductor.repos=character(0)",
    D = "Blocked + R_BIOC_VERSION env var",
    E = "Blocked + renv::settings$bioconductor.version()",
    F = "Blocked + non-empty stub repos",
    G = "Blocked + BioC_mirror + BIOCONDUCTOR_CONFIG_FILE",
    H = "Blocked + manual lockfile patch"
  )

  for (s in scenarios) {
    r <- results[[s]]
    bioc_blocked <- if (s == "A") "No" else "Yes"
    ppm_ok    <- if (isTRUE(r$ppm_access)) "Yes" else "No"
    bioc_refs <- if (isTRUE(r$lockfile_has_bioc_refs)) "Yes" else "No"
    startup   <- r$startup_status  %||% "—"
    snapshot  <- r$snapshot_status %||% "—"
    restore   <- r$restore_status  %||% "—"
    reintr    <- r$lockfile_reintroduced_by %||% "—"
    report_lines <- c(report_lines,
      sprintf("| **%s** %s | %s | %s | %s | %s | %s | %s | %s |",
              s, scenario_desc[[s]], bioc_blocked, ppm_ok, bioc_refs,
              startup, snapshot, restore, reintr))
  }

  report_lines <- c(report_lines, "", "---", "", "## Scenario Details", "")

  for (s in scenarios) {
    r   <- results[[s]]
    env <- read_json_safe(file.path(artifacts_root, s, "env_diagnostics.json"))

    report_lines <- c(report_lines,
      paste0("### Scenario ", s, ": ", scenario_desc[[s]]),
      "",
      paste0("**PPM reachable**: ", if (isTRUE(r$ppm_access)) "Yes" else "No"),
      paste0("**Bioconductor reachable**: ", if (isTRUE(r$bioc_access)) "Yes" else "No"),
      ""
    )

    lock_path <- file.path(artifacts_root, s, "renv.lock")
    if (file.exists(lock_path)) {
      # Show actual Bioconductor section/repos lines (not renv's embedded metadata)
      lock_obj <- tryCatch(jsonlite::fromJSON(lock_path, simplifyVector = FALSE), error = function(e) NULL)
      bioc_lines <- character(0)
      if (!is.null(lock_obj)) {
        if (!is.null(lock_obj$Bioconductor)) {
          bioc_lines <- c(bioc_lines, paste0("Bioconductor.Version: ", lock_obj$Bioconductor$Version))
        }
        bioc_repos <- Filter(function(r) grepl("bioconductor\\.org", r$URL %||% "", ignore.case=TRUE),
                             lock_obj$R$Repositories %||% list())
        if (length(bioc_repos) > 0) {
          bioc_lines <- c(bioc_lines, paste0("Repository: ", sapply(bioc_repos, function(r) paste0(r$Name, " = ", r$URL))))
        }
      }
      if (length(bioc_lines) > 0) {
        report_lines <- c(report_lines,
          "**Bioconductor-related lockfile entries:**",
          "```",
          bioc_lines,
          "```",
          "")
      } else {
        report_lines <- c(report_lines, "**Lockfile**: No Bioconductor section or repos.", "")
      }
    }

    if (!is.null(r$key_error_message) && !is.na(r$key_error_message)) {
      report_lines <- c(report_lines,
        paste0("**Key error**: `", r$key_error_message, "`"),
        "")
    }

    if (s == "H") {
      report_lines <- c(report_lines,
        paste0("**Lockfile re-introduced by**: ", r$lockfile_reintroduced_by %||% "unknown"),
        "")

      # Show diff for H
      before_path <- file.path(artifacts_root, s, "lockfile_before_patch.json")
      after_path  <- file.path(artifacts_root, s, "lockfile_after_patch.json")
      if (file.exists(before_path) && file.exists(after_path)) {
        before_lines <- readLines(before_path)
        after_lines  <- readLines(after_path)
        before_bioc  <- before_lines[grepl("bioconductor|Bioconductor", before_lines)]
        after_bioc   <- after_lines[grepl("bioconductor|Bioconductor", after_lines)]
        report_lines <- c(report_lines,
          "**Bioc lines before patch:**",
          "```",
          head(before_bioc, 15),
          "```",
          "**Bioc lines after patch:**",
          "```",
          if (length(after_bioc) > 0) head(after_bioc, 15) else "(none)",
          "```",
          "")
      }
    }
  }

  # Classify error types per scenario
  error_A <- results[["A"]]$key_error_message %||% ""

  snap_warn  <- Filter(function(s) isTRUE(results[[s]]$snapshot_status == "warning"),  scenarios)
  snap_fail  <- Filter(function(s) s != "A" && isTRUE(results[[s]]$snapshot_status == "failure"), scenarios)
  reintr_h   <- results[["H"]]$lockfile_reintroduced_by %||% "unknown"

  report_lines <- c(report_lines,
    "---",
    "",
    "## Conclusion",
    "",
    "### Root cause",
    "",
    "The `recipes` CRAN package includes a `biocViews: mixOmics` field in its DESCRIPTION.",
    "renv 1.2.3 treats any installed package with `biocViews` as a Bioconductor package.",
    "This triggers two distinct failure paths in `renv::snapshot()`:",
    "",
    "1. **Open network (Scenario A):** renv's pre-flight check requires `BiocVersion` to be",
    "   installed before snapshotting any project that contains a biocViews package.",
    "   `BiocVersion` is only available from Bioconductor, not from PPM.",
    "   Error: `aborting snapshot due to pre-flight validation failure`",
    "",
    "2. **Bioc-blocked network (Scenario B):** renv calls BiocManager to validate/resolve",
    "   the Bioconductor version before snapshot. With bioconductor.org unreachable,",
    "   BiocManager cannot validate and snapshot aborts.",
    "   Error: `Bioconductor version cannot be validated; no internet connection?`",
    "",
    "Neither failure requires the user to have explicitly opted into Bioconductor.",
    "Simply having `recipes` in `project.R` is sufficient to trigger it.",
    "",
    "### Snapshot failure by scenario",
    "",
    if (length(snap_fail) > 0)
      paste0("- **Hard failure** (error): Scenarios ", paste(snap_fail, collapse = ", "))
    else
      "- No hard failures.",
    if (length(snap_warn) > 0)
      paste0("- **Soft failure** (warning, incomplete lockfile): Scenarios ", paste(snap_warn, collapse = ", "))
    else
      "",
    "",
    "### Workaround analysis",
    "",
    "| Scenario | Approach | Snapshot outcome | Key error |",
    "|---|---|---|---|",
    "| B | None (default) | failure | BiocManager version validation fails (network) |",
    "| C | `renv.bioconductor.repos=character(0)` | failure | BiocVersion preflight still runs |",
    "| D | `R_BIOC_VERSION=3.20` env var | failure | Bypasses version check but renv still fetches Bioc repo indices |",
    "| E | `settings$bioconductor.version('3.20')` | warning | BiocManager not invoked for version; snapshot writes but excludes recipes |",
    "| F | Stub bioc repo URLs | failure | BiocVersion preflight still runs |",
    "| G | `BioC_mirror` + `BIOCONDUCTOR_CONFIG_FILE` | failure | Config file parsed but version map validation fails |",
    "| H | Manual lockfile patch | failure | Patch works but next snapshot call fails again |",
    "",
    "### What action re-adds Bioc refs after manual lockfile patch",
    "",
    paste0("- Scenario H result: **", reintr_h,
      "** — startup and restore succeed with a patched lockfile,",
      " but snapshot always fails again (BiocManager is invoked on every snapshot call)."),
    "",
    "### Recommended mitigation",
    "",
    "No single option tested here fully prevents renv from invoking Bioconductor machinery",
    "when `recipes` (or any package with `biocViews`) is in the project. Options to explore",
    "with Posit Support:",
    "",
    "- **Install BiocVersion from PPM** if PPM mirrors it — satisfies the preflight check",
    "  without reaching bioconductor.org.",
    "- **`renv::settings$bioconductor.version('3.20')`** (Scenario E) reduces the failure",
    "  from hard error to warning and avoids the network call, but the lockfile is incomplete.",
    "- **Exclude the `biocViews`-bearing package from snapshot** and manage it separately.",
    "- **File an renv issue**: the current behaviour of requiring BiocVersion for any package",
    "  that has `biocViews` (even CRAN packages installed from PPM) appears unintentional.",
    ""
  )

  writeLines(report_lines, file.path(artifacts_root, "report.md"))
  cat("Wrote artifacts/report.md\n")
}

cat("\nDone.\n")
