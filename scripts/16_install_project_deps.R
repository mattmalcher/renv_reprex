# 16_install_project_deps.R — Path A (scenario 8): the project IS the package.
#
# Setup + failure in one file. The project itself is a package whose DESCRIPTION
# carries a non-empty biocViews field (the cranlike-with-biocviews fixture). We
# make /project that package, init renv (bare, so deps aren't auto-installed),
# then install the project's declared dependencies.
#
# renv's dependency discovery injects BiocManager + BiocVersion as implicit
# dependencies (dependencies.R:602). Installing them then fails: BiocVersion is a
# Bioconductor-only package, and with bioconductor.org blocked it cannot be
# downloaded — even though the project otherwise uses only base/CRAN.
#
# This is the install/restore-time counterpart to Path B's snapshot-time failure
# (scenario 4). A bare renv::snapshot() of this project would NOT fail (BiocVersion
# is merely discovered, never installed, so the snapshot-time Bioconductor
# validation never fires) — the breakage is at install/restore.

source("/scripts/_common.R")
fixture <- Sys.getenv("FIXTURE", "cranlike-with-biocviews")

cat("=== 16_install_project_deps ===\n")
cat("Scenario:", scenario, "\n")
cat("Fixture (used as the project package):", fixture, "\n\n")

library(renv)
library(jsonlite)

# 0. Make /project the package: copy the fixture in, then init renv bare.
src <- file.path("/fixtures", fixture)
for (item in list.files(src, full.names = TRUE))
  file.copy(item, ".", recursive = TRUE, overwrite = TRUE)
cat("Project now contains:\n"); print(list.files(".", recursive = TRUE))
cat("\n--- project DESCRIPTION ---\n")
cat(paste(readLines("DESCRIPTION"), collapse = "\n"), "\n\n")

cat("renv::init(bare = TRUE)  # do not auto-install deps; isolate the failure to install\n\n")
renv::init(bare = TRUE, restart = FALSE)

# 1. Prove the injection: dependency discovery over the project DESCRIPTION.
cat("\nRunning renv::dependencies() on the project...\n")
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
write_json(list(
  operation                     = "renv::install()",
  result                        = if (is.null(install_error)) "ok (but dependency missing)" else paste0("error: ", install_error),
  biocmanager_discovered        = biocmanager_found,
  biocversion_discovered        = biocversion_found,
  snapshot_status               = status,
  snapshot_error_classification = classify(install_error, install_warnings),
  snapshot_warnings             = install_warnings,
  renv_lock_written             = file.exists("renv.lock"),
  target_package                = "BiocVersion",
  target_package_recorded       = biocversion_installed
), "snapshot_result.json")

cat("\nDone.\n")
