`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

scenario       <- Sys.getenv("SCENARIO", "unknown")
artifacts_root <- "/artifacts"

cat("=== 70_collect_artifacts ===\n")
cat("Scenario:", scenario, "\n\n")

read_json_safe <- function(path) {
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
}

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
# Scenarios 1-3 write their own result.json — skip overwriting those.
# Scenarios 4-7 always write here.
result_path <- file.path(out_dir, "result.json")
if (!file.exists(result_path) || !(scenario %in% c("1", "2", "3"))) {
  env  <- read_json_safe(file.path(out_dir, "env_diagnostics.json"))
  snap <- read_json_safe(file.path(out_dir, "snapshot_result.json"))

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

  # biocViews present at snapshot time: scenarios 4/6/7 (metaRNASeq, intact),
  # 8 (project-as-package fixture). Scenario 5 strips it from the DESCRIPTION.
  biocviews_present <- scenario %in% c("4", "6", "7", "8")

  snap_status  <- snap$snapshot_status %||% "unknown"
  lock_written <- file.exists(file.path(out_dir, "renv.lock")) ||
                  isTRUE(snap$renv_lock_written)

  result <- list(
    scenario                      = scenario,
    operation                     = snap$operation %||% "renv::snapshot()",
    ppm_reachable                 = isTRUE(env$ppm_access),
    bioconductor_reachable        = isTRUE(env$bioc_access),
    biocviews_present             = biocviews_present,
    biocmanager_discovered        = biocmanager_found,
    biocversion_discovered        = biocversion_found,
    snapshot_status               = snap_status,
    snapshot_error_classification = snap$snapshot_error_classification %||% NA,
    snapshot_warnings             = snap$snapshot_warnings %||% NA,
    target_package                = snap$target_package %||% NA,
    target_package_recorded       = snap$target_package_recorded %||% NA,
    biocversion_in_lock           = snap$biocversion_in_lock %||% NA,
    bioc_source_tagged            = snap$bioc_source_tagged %||% NA,
    renv_lock_written             = lock_written,
    notes                         = ""
  )
  writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
             result_path)
  cat("Wrote result.json\n")

  # Clean up intermediate files now that result.json captures their content
  for (f in c("snapshot_result.json", "env_diagnostics.json")) {
    p <- file.path(out_dir, f)
    if (file.exists(p)) file.remove(p)
  }
} else {
  cat("result.json already present — skipping\n")
}

cat("\nOutcome:\n")
cat(paste(readLines(result_path), collapse = "\n"), "\n")

cat("\nDone.\n")
