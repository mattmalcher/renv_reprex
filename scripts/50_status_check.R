# 50_status_check.R — Path C: the project is out of sync even after snapshot succeeds.
#
# Runs in scenario 11's snapshot phase, AFTER 30_snapshot.R. The customer's report
# (support thread): once the short-circuit options silence the bioconductor.org
# probe, renv::snapshot() completes — but renv::status() then shows BiocManager and
# BiocVersion in inconsistent states, so renv::activate() reports the project out of
# sync on every startup.
#
# Mechanism: metaRNASeq's biocViews makes renv inject BiocManager + BiocVersion as
# project dependencies (dependencies.R:602). On a CRAN/PPM-only host they can never
# be installed, so they are perpetually "used in the project but not installed" —
# the exact relationship renv::status() flags as out of sync. This persists no
# matter how the network timeout is worked around; only removing the biocViews
# trigger (scenario 5) clears it.

source("/scripts/_common.R")
target <- Sys.getenv("PACKAGE", "metaRNASeq")

cat("=== 50_status_check ===\n")
cat("Scenario:", scenario, "\n")
cat("Target package:", target, "\n\n")

library(renv)
library(jsonlite)

# --- renv::status(), captured without letting warnings unwind the call ----------
status_output <- character()
status_obj    <- NULL
withCallingHandlers(
  status_output <- capture.output(
    status_obj <- tryCatch(
      renv::status(),
      error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL }
    )
  ),
  warning = function(w) {
    cat("WARNING:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }
)
cat("--- renv::status() output ---\n")
cat(paste(status_output, collapse = "\n"), "\n\n")

# renv::status() returns a list with $synchronized in renv 1.x.
synchronized <- if (!is.null(status_obj) && !is.null(status_obj$synchronized))
  isTRUE(status_obj$synchronized) else NA

# --- which packages are inconsistent (used as a dependency but not installed) ---
deps <- tryCatch(renv::dependencies(progress = FALSE, errors = "ignored"),
                 error = function(e) NULL)
used <- if (!is.null(deps) && "Package" %in% names(deps)) unique(deps$Package) else character()

recorded <- character()
if (file.exists("renv.lock")) {
  lock <- tryCatch(jsonlite::fromJSON("renv.lock", simplifyVector = FALSE),
                   error = function(e) NULL)
  if (!is.null(lock) && !is.null(lock$Packages)) recorded <- names(lock$Packages)
}

pkg_state <- function(p) list(
  package      = p,
  used_in_deps = p %in% used,
  installed    = requireNamespace(p, quietly = TRUE),
  in_lockfile  = p %in% recorded
)
biocmanager <- pkg_state("BiocManager")
biocversion <- pkg_state("BiocVersion")

# "inconsistent" = renv considers it part of the project but it is not installed.
is_inconsistent <- function(s) isTRUE(s$used_in_deps) && !isTRUE(s$installed)
biocmanager_inconsistent <- is_inconsistent(biocmanager)
biocversion_inconsistent <- is_inconsistent(biocversion)

out_of_sync <- isFALSE(synchronized) || biocmanager_inconsistent || biocversion_inconsistent

cat("--- status assessment ---\n")
cat("synchronized:", synchronized, "\n")
cat("BiocManager  used/installed/in-lock:",
    biocmanager$used_in_deps, biocmanager$installed, biocmanager$in_lockfile, "\n")
cat("BiocVersion  used/installed/in-lock:",
    biocversion$used_in_deps, biocversion$installed, biocversion$in_lockfile, "\n")
cat("BiocManager inconsistent:", biocmanager_inconsistent, "\n")
cat("BiocVersion inconsistent:", biocversion_inconsistent, "\n")
cat("project out of sync:", out_of_sync, "\n\n")

write_json(list(
  synchronized             = synchronized,
  project_out_of_sync      = out_of_sync,
  biocmanager              = biocmanager,
  biocversion              = biocversion,
  biocmanager_inconsistent = biocmanager_inconsistent,
  biocversion_inconsistent = biocversion_inconsistent,
  status_output            = status_output
), "status_result.json")

cat("Wrote status_result.json\n\nDone.\n")
