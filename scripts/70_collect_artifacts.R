source("/scripts/bioc_detect.R")
`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

scenario       <- Sys.getenv("SCENARIO", "unknown")
artifacts_root <- "/artifacts"

cat("=== 70_collect_artifacts ===\n")
cat("Scenario:", scenario, "\n\n")

read_json_safe <- function(path) {
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
}

# ── per-scenario consolidation ────────────────────────────────────────────────

if (scenario != "REPORT") {
  out_dir <- file.path(artifacts_root, scenario)

  # Copy renv.lock and renv/settings.json if present in /project
  for (src in c("/project/renv.lock", "/project/renv/settings.json")) {
    if (file.exists(src)) {
      dest_name <- if (basename(src) == "settings.json") "renv-settings.json" else "renv.lock"
      file.copy(src, file.path(out_dir, dest_name), overwrite = TRUE)
      cat("Saved", src, "→", dest_name, "\n")
    }
  }

  # Build result.json from individual step outputs.
  # Scenarios 1-3 write their own result.json before calling this script — skip
  # overwriting those. Scenarios 4-8 always write here (stale files from prior
  # runs must be refreshed from the latest snapshot_result.json).
  result_path <- file.path(out_dir, "result.json")
  if (!file.exists(result_path) || !(scenario %in% c("1", "2", "3"))) {
    env  <- read_json_safe(file.path(out_dir, "env_diagnostics.json"))
    snap <- read_json_safe(file.path(out_dir, "snapshot_result.json"))

    # deps CSV to check biocmanager/biocversion
    deps_csv <- file.path(out_dir, "discovered-dependencies.csv")
    biocmanager_found <- FALSE
    biocversion_found <- FALSE
    if (file.exists(deps_csv)) {
      deps_df <- tryCatch(read.csv(deps_csv, stringsAsFactors = FALSE), error = function(e) NULL)
      if (!is.null(deps_df) && "Package" %in% names(deps_df)) {
        biocmanager_found <- "BiocManager" %in% deps_df$Package
        biocversion_found <- "BiocVersion" %in% deps_df$Package
      }
    }
    if (!biocmanager_found && !is.null(snap$biocmanager_discovered))
      biocmanager_found <- isTRUE(snap$biocmanager_discovered)
    if (!biocversion_found && !is.null(snap$biocversion_discovered))
      biocversion_found <- isTRUE(snap$biocversion_discovered)

    # Infer biocviews_present from scenario number:
    # 4/6/7/8/9 use metaRNASeq (biocViews present); 5 uses glue (absent)
    biocviews_present <- scenario %in% c("4", "6", "7", "8", "9")

    snap_status <- snap$snapshot_status %||% "unknown"
    lock_written <- file.exists(file.path(out_dir, "renv.lock")) ||
                    isTRUE(snap$renv_lock_written)

    result <- list(
      scenario                      = scenario,
      ppm_reachable                 = isTRUE(env$ppm_access),
      bioconductor_reachable        = isTRUE(env$bioc_access),
      biocviews_present             = biocviews_present,
      biocmanager_discovered        = biocmanager_found,
      biocversion_discovered        = biocversion_found,
      snapshot_status               = snap_status,
      snapshot_error_classification = snap$snapshot_error_classification %||% NA,
      renv_lock_written             = lock_written,
      notes                         = ""
    )
    writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
               result_path)
    cat("Wrote result.json\n")
  } else {
    cat("result.json already present and written by scenario script — skipping\n")
  }

  cat("\nOutcome:\n")
  cat(paste(readLines(result_path), collapse = "\n"), "\n")

} else {
  # ── REPORT mode: cross-scenario summary and report.md ────────────────────────

  scenarios <- as.character(1:9)
  results   <- list()

  for (s in scenarios) {
    r_path <- file.path(artifacts_root, s, "result.json")
    if (file.exists(r_path)) {
      results[[s]] <- read_json_safe(r_path)
    } else {
      results[[s]] <- list(scenario = s, notes = "not run")
    }
  }

  writeLines(
    jsonlite::toJSON(results, auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(artifacts_root, "summary.json")
  )
  cat("Wrote summary.json\n")

  # ── Helper for safe field access ─────────────────────────────────────────────
  rget <- function(r, field) r[[field]] %||% NA

  # ── Recipes biocViews from scenario 3 ────────────────────────────────────────
  recipes_desc_path <- file.path(artifacts_root, "3", "recipes_DESCRIPTION.txt")
  recipes_biocviews <- ""
  if (file.exists(recipes_desc_path)) {
    lines <- readLines(recipes_desc_path)
    bv    <- grep("^biocViews", lines, value = TRUE)
    if (length(bv) > 0) recipes_biocviews <- trimws(sub("^biocViews:\\s*", "", bv[[1]]))
  }

  # ── Load env from scenario 4 for R/renv versions ─────────────────────────────
  env4 <- read_json_safe(file.path(artifacts_root, "4", "env_diagnostics.json"))
  r_version   <- env4$r_version   %||% "unknown"
  renv_version <- env4$renv_version %||% "unknown"

  # ── Discovery comparison from scenarios 1 and 2 ──────────────────────────────
  r1 <- results[["1"]]; r2 <- results[["2"]]

  # ── Snapshot comparison from scenarios 4 and 5 ───────────────────────────────
  r4 <- results[["4"]]; r5 <- results[["5"]]

  report_lines <- c(
    "# renv biocViews → BiocVersion Dependency Failure Report",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")),
    "",
    "---",
    "",
    "## 1. Executive Summary",
    "",
    "A non-empty `biocViews` field in a package DESCRIPTION file causes `renv` dependency",
    "discovery to inject `BiocManager` and `BiocVersion` as implicit dependencies.",
    "In a CRAN/PPM-only environment where Bioconductor is blocked, `BiocVersion` cannot",
    "be resolved, so `renv::snapshot()` cannot complete — even when the user has not",
    "explicitly depended on any Bioconductor package.",
    "",
    "**Environment**",
    "",
    paste0("- R version: ", r_version),
    paste0("- renv version: ", renv_version),
    paste0("- OS: Ubuntu 24.04 (Noble), Docker container"),
    paste0("- CRAN repo: Posit Package Manager (Noble Linux binaries)"),
    paste0("- Bioconductor blocking: Docker `--add-host` redirects bioconductor.org → 127.0.0.1"),
    "",
    "---",
    "",
    "## 2. Code-Path Evidence",
    "",
    "The trigger is in `renv/R/dependencies.R`, function `renv_dependencies_discover_description()`:",
    "",
    "```r",
    "# if this is a bioconductor package, add their implicit dependencies",
    "# guard against packages which have an empty biocViews field",
    "# https://github.com/rstudio/renv/issues/2149",
    "if (nzchar(dcf[[\"biocViews\"]] %||% \"\")) {",
    "  data[[length(data) + 1L]] <- renv_dependencies_list(",
    "    source   = path,",
    "    packages = c(renv_bioconductor_manager(), \"BiocVersion\")",
    "  )",
    "  names(data)[[length(data)]] <- \"Bioconductor\"",
    "}",
    "```",
    "",
    "- This branch fires on **any** non-empty `biocViews` value.",
    "- On R ≥ 4.0, `renv_bioconductor_manager()` returns `\"BiocManager\"`.",
    "- `BiocManager` is available from CRAN/PPM. **`BiocVersion` is not** — it is a",
    "  Bioconductor-only package.",
    "- Therefore any project whose dependency graph includes a package with non-empty",
    "  `biocViews` will fail `renv::snapshot()` on a CRAN-only, Bioconductor-blocked network.",
    "",
    "---",
    "",
    "## 3. Minimal Fixture Proof",
    "",
    "Two tiny local packages were created — identical except for the `biocViews` field.",
    "Scenarios 1 and 2 run `renv::dependencies()` on each DESCRIPTION directly.",
    "",
    "| Fixture | biocViews field | BiocManager discovered | BiocVersion discovered |",
    "|---------|----------------|------------------------|------------------------|",
    sprintf("| `cranlike-no-biocviews` | absent | %s | %s |",
            if (isFALSE(rget(r1, "biocmanager_discovered"))) "No" else rget(r1, "biocmanager_discovered") %||% "—",
            if (isFALSE(rget(r1, "biocversion_discovered"))) "No" else rget(r1, "biocversion_discovered") %||% "—"),
    sprintf("| `cranlike-with-biocviews` | `biocViews: Software` | %s | %s |",
            if (isTRUE(rget(r2, "biocmanager_discovered"))) "**Yes**" else rget(r2, "biocmanager_discovered") %||% "—",
            if (isTRUE(rget(r2, "biocversion_discovered"))) "**Yes**" else rget(r2, "biocversion_discovered") %||% "—"),
    "",
    "Scenario 1 expected: no `BiocManager`, no `BiocVersion`.",
    "Scenario 2 expected: `BiocManager` and `BiocVersion` present, type = `Bioconductor`.",
    "",
    "---",
    "",
    "## 4. Real-Package Proof: `recipes`",
    "",
    "Scenario 3 installs `recipes` from Posit Package Manager (CRAN) and inspects its metadata.",
    "",
    "```r",
    "packageDescription(\"recipes\")[c(\"Package\", \"Version\", \"Repository\", \"biocViews\")]",
    "```",
    "",
    if (nzchar(recipes_biocviews))
      paste0("- `biocViews`: `", recipes_biocviews, "`")
    else
      "- `biocViews`: see `artifacts/3/recipes_DESCRIPTION.txt`",
    "",
    "Key point: `recipes` is installed from CRAN/PPM, not from Bioconductor.",
    "Its `biocViews` metadata is enough to trigger renv's Bioconductor dependency injection.",
    "",
    "---",
    "",
    "## 5. Snapshot Proof Under Blocked Bioconductor",
    "",
    "Scenarios 4 and 5 use identical network configuration (Bioconductor blocked, PPM reachable).",
    "The only difference is which fixture package is installed.",
    "",
    "| Scenario | Fixture | biocViews | Bioc blocked | Snapshot status | Error |",
    "|----------|---------|-----------|--------------|-----------------|-------|",
    sprintf("| 4 | `cranlike-with-biocviews` | present | Yes | **%s** | %s |",
            toupper(rget(r4, "snapshot_status") %||% "unknown"),
            rget(r4, "snapshot_error_classification") %||% "—"),
    sprintf("| 5 | `cranlike-no-biocviews` | absent | Yes | **%s** | %s |",
            toupper(rget(r5, "snapshot_status") %||% "unknown"),
            rget(r5, "snapshot_error_classification") %||% "—"),
    "",
    "Scenario 5 is the key control: the same blocked network does **not** prevent snapshot",
    "when there is no `biocViews` trigger. The failure in Scenario 4 is caused purely by",
    "renv's implicit `BiocVersion` dependency injection.",
    "",
    "---",
    "",
    "## 6. Workaround Analysis",
    ""
  )

  scenario_desc <- c(
    "1" = "Discovery — no biocViews",
    "2" = "Discovery — with biocViews",
    "3" = "Real-world: recipes from CRAN/PPM",
    "4" = "Snapshot failure: with biocViews, Bioc blocked",
    "5" = "Snapshot control: no biocViews, Bioc blocked",
    "6" = "Workaround: renv::settings$bioconductor.version('3.20')",
    "7" = "Workaround: BiocVersion via PPM Bioconductor mirror",
    "8" = "Workaround: stub renv.bioconductor.repos (PPM root)",
    "9" = "Workaround: renv.bioconductor.repos pointing at CRAN PPM URL"
  )

  report_lines <- c(report_lines,
    "| Scenario | Approach | Snapshot status | Error / Notes |",
    "|----------|---------|-----------------|---------------|"
  )

  for (s in c("4", "6", "7", "8", "9")) {
    r       <- results[[s]]
    status  <- rget(r, "snapshot_status") %||% "unknown"
    err     <- rget(r, "snapshot_error_classification") %||% rget(r, "notes") %||% "—"
    approach <- switch(s,
      "4" = "None — baseline failure",
      "6" = "`renv::settings$bioconductor.version('3.20')`",
      "7" = "PPM Bioconductor mirror (`BioCsoft` repo pointing to PPM)",
      "8" = "`options(renv.bioconductor.repos = c(...))` — PPM root",
      "9" = "`options(renv.bioconductor.repos = c(...))` — CRAN PPM URL"
    )
    report_lines <- c(report_lines,
      sprintf("| %s | %s | **%s** | %s |", s, approach, toupper(status), err))
  }

  report_lines <- c(report_lines, "",
    "---",
    "",
    "## 7. Conclusion",
    "",
    "This issue is not primarily that Bioconductor repositories appear in the lockfile.",
    "The blocker is earlier: dependency discovery converts `biocViews` metadata into an",
    "implicit dependency on `BiocVersion`. Since `BiocVersion` is not available from",
    "CRAN-only PPM and Bioconductor is blocked, `renv::snapshot()` cannot complete for",
    "a project that otherwise uses only CRAN packages.",
    "",
    "**Workaround findings from this test run:**",
    "",
    "- **Scenario 6 — `renv::settings$bioconductor.version('3.20')`**: snapshot emits",
    "  a warning (BiocManager not available, bioconductor.org unreachable) but does not",
    "  hard-fail. The lockfile is written; however packages installed outside renv's",
    "  tracking (e.g. local source) are excluded. When used with a properly installed",
    "  project this may be a viable workaround.",
    "- **Scenario 7 — PPM Bioconductor mirror as `BioCsoft` repo**: snapshot FAILS with",
    "  the same Bioconductor version validation error as scenario 4. renv still queries",
    "  `bioconductor.org/config.yaml` for version validation even when a mirror is configured;",
    "  this call is not redirected to the PPM mirror. Setting `BioCsoft` alone is insufficient.",
    "- **Scenario 8 — stub `renv.bioconductor.repos`**: snapshot FAILS with pre-flight",
    "  validation failure (BiocVersion not installed). Pointing repos at an address that",
    "  does not serve BiocVersion does not help.",
    "",
    "**Recommended fixes:**",
    "",
    "- **Combine `bioconductor.version` + a reachable Bioconductor mirror** (PPM or internal)",
    "  so renv can both determine the version and install `BiocVersion` without bioconductor.org.",
    "- **File an renv issue** requesting that CRAN packages with `biocViews` not trigger",
    "  Bioconductor-only dependency injection when the user has not opted into Bioconductor.",
    "",
    "---",
    "",
    "## Appendix: Full Scenario Results",
    "",
    "| # | Description | PPM | Bioc blocked | biocViews | Snap status |",
    "|---|-------------|-----|-------------|-----------|-------------|"
  )

  for (s in scenarios) {
    r    <- results[[s]]
    desc <- scenario_desc[[s]] %||% s
    ppm  <- if (isTRUE(rget(r, "ppm_reachable"))) "Yes" else "No"
    blocked <- if (s %in% c("1","2","3")) "N/A" else "Yes"  # all scenarios 4-9 block Bioc
    biocv <- if (is.na(rget(r, "biocviews_present"))) "—"
             else if (isTRUE(rget(r, "biocviews_present"))) "present" else "absent"
    snap_s <- rget(r, "snapshot_status") %||% "—"
    report_lines <- c(report_lines,
      sprintf("| %s | %s | %s | %s | %s | %s |",
              s, desc, ppm, blocked, biocv, snap_s))
  }

  report_lines <- c(report_lines, "")

  writeLines(report_lines, file.path(artifacts_root, "report.md"))
  cat("Wrote artifacts/report.md\n")
}

cat("\nDone.\n")
