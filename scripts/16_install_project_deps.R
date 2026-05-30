# 16_install_project_deps.R — Path A failure (scenario 8).
#
# The project IS a package whose DESCRIPTION carries biocViews. renv's dependency
# discovery injects BiocManager + BiocVersion as implicit dependencies
# (dependencies.R:602). Installing the project's declared dependencies then fails:
# BiocVersion is a Bioconductor-only package, and with bioconductor.org blocked it
# cannot be downloaded — even though the project otherwise uses only base/CRAN.
#
# This is the install/restore-time counterpart to Path B's snapshot-time failure
# (scenario 4). A bare renv::snapshot() of this project would NOT fail (BiocVersion
# is merely discovered, never installed, so the snapshot-time Bioconductor
# validation never fires) — the breakage is at install/restore.

`%||%` <- function(x, y) if (is.null(x)) y else x

scenario <- Sys.getenv("SCENARIO", "8")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 16_install_project_deps ===\n")
cat("Scenario:", scenario, "\n\n")

library(renv)
library(jsonlite)

# 1. Prove the injection: dependency discovery over the project DESCRIPTION.
cat("Running renv::dependencies() on the project...\n")
deps <- tryCatch(renv::dependencies(progress = FALSE, errors = "ignored"),
                 error = function(e) { cat("WARNING:", conditionMessage(e), "\n"); NULL })
if (!is.null(deps) && nrow(deps) > 0) {
  write.csv(deps, file.path(out_dir, "discovered-dependencies.csv"), row.names = FALSE)
  print(deps)
}
biocmanager_found <- !is.null(deps) && "BiocManager" %in% deps$Package
biocversion_found <- !is.null(deps) && "BiocVersion" %in% deps$Package
cat("\nBiocManager discovered:", biocmanager_found, "\n")
cat("BiocVersion discovered:", biocversion_found, "\n\n")

# 2. The failure: install the project's declared dependencies.
cat("Running renv::install() to install the project's dependencies...\n")
install_warnings <- character()
install_error    <- NULL
withCallingHandlers(
  tryCatch(
    renv::install(),
    error = function(e) {
      install_error <<- conditionMessage(e)
      cat("ERROR:", conditionMessage(e), "\n")
    }
  ),
  warning = function(w) {
    install_warnings <<- c(install_warnings, conditionMessage(w))
    cat("WARNING:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }
)

biocversion_installed <- requireNamespace("BiocVersion", quietly = TRUE)
cat("\nBiocVersion actually installed:", biocversion_installed, "\n")

status <- if (!is.null(install_error) || !biocversion_installed) "failure" else "success"
cat("Install status:", status, "\n")

classify <- function(msg, warns) {
  hay <- tolower(paste(c(msg, warns), collapse = " "))
  if (grepl("biocversion", hay))                       "BiocVersion dependency not available"
  else if (grepl("cannot be validated", hay))          "Bioconductor version validation failed"
  else if (grepl("failed to download|not available", hay)) "Dependency download failed"
  else if (nzchar(hay))                                hay
  else                                                 NA_character_
}

# Write a snapshot_result.json so 70_collect_artifacts assembles result.json
# uniformly. operation = "renv::install()" distinguishes Path A from Path B.
writeLines(
  toJSON(list(
    operation                     = "renv::install()",
    result                        = if (is.null(install_error)) "ok (but dependency missing)" else paste0("error: ", install_error),
    biocmanager_discovered        = biocmanager_found,
    biocversion_discovered        = biocversion_found,
    snapshot_status               = status,
    snapshot_error_classification = classify(install_error, install_warnings),
    snapshot_warnings             = install_warnings,
    renv_lock_written             = file.exists("renv.lock"),
    target_package                = "BiocVersion",
    target_package_recorded       = biocversion_installed,
    biocversion_in_lock           = FALSE,
    bioc_source_tagged            = FALSE
  ), auto_unbox = TRUE, pretty = TRUE, na = "null"),
  file.path(out_dir, "snapshot_result.json")
)

cat("\nDone.\n")
