source("/scripts/_common.R")
target <- Sys.getenv("PACKAGE", "")            # package whose presence in the lock = success

cat("=== 30_snapshot ===\n")
cat("Scenario:", scenario, "\n")
cat("Target package:", if (nzchar(target)) target else "(none)", "\n\n")

library(renv)
library(jsonlite)

# Capture discovered dependencies before snapshot
cat("Running renv::dependencies() to capture dependency list...\n")
deps <- tryCatch(
  renv::dependencies(progress = FALSE, errors = "ignored"),
  error = function(e) {
    cat("WARNING from renv::dependencies():", conditionMessage(e), "\n")
    NULL
  }
)

if (!is.null(deps) && nrow(deps) > 0) {
  write.csv(deps, file.path(out_dir, "discovered-dependencies.csv"), row.names = FALSE)
  cat("Wrote discovered-dependencies.csv\n")
  biocmanager_found <- "BiocManager" %in% deps$Package
  biocversion_found <- "BiocVersion" %in% deps$Package
} else {
  write.csv(
    data.frame(Source = character(), Package = character(), Require = character(),
               Version = character(), Dev = logical()),
    file.path(out_dir, "discovered-dependencies.csv"),
    row.names = FALSE
  )
  biocmanager_found <- FALSE
  biocversion_found <- FALSE
}

cat("BiocManager in discovered deps:", biocmanager_found, "\n")
cat("BiocVersion in discovered deps:", biocversion_found, "\n\n")

# Run snapshot.
#
# IMPORTANT: renv::snapshot() emits warnings as part of normal operation, so we
# must NOT let the first warning unwind the call (a tryCatch(warning=) handler
# would do exactly that and make a merely-warned snapshot look identical to an
# aborted one). Instead we capture warnings with withCallingHandlers + muffle,
# let snapshot run to completion, and judge success by what actually lands in
# the lockfile — not by whether a warning was raised.
cat("Running renv::snapshot()...\n")
snap_warnings <- character()
snap_error    <- NULL
withCallingHandlers(
  tryCatch(
    renv::snapshot(prompt = FALSE),
    error = function(e) {
      snap_error <<- conditionMessage(e)
      cat("ERROR:", conditionMessage(e), "\n")
    }
  ),
  warning = function(w) {
    snap_warnings <<- c(snap_warnings, conditionMessage(w))
    cat("WARNING:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }
)

# Inspect the resulting lockfile: the real test of success is whether the
# project's target package was actually recorded.
recorded_packages <- character()
if (file.exists("renv.lock")) {
  lock <- tryCatch(jsonlite::fromJSON("renv.lock", simplifyVector = FALSE),
                   error = function(e) NULL)
  if (!is.null(lock) && !is.null(lock$Packages))
    recorded_packages <- names(lock$Packages)
  file.copy("renv.lock", file.path(out_dir, "renv.lock"), overwrite = TRUE)
}
target_recorded <- nzchar(target) && target %in% recorded_packages

cat("\n--- lockfile assessment ---\n")
cat("Recorded packages:", if (length(recorded_packages)) paste(recorded_packages, collapse = ", ") else "(none)", "\n")
cat("Target recorded:", if (nzchar(target)) target_recorded else NA, "\n\n")

if (file.exists("renv/settings.json")) {
  file.copy("renv/settings.json", file.path(out_dir, "renv-settings.json"), overwrite = TRUE)
}

# Three-way status, judged on the error + the lockfile contents:
#   failure    — snapshot raised an error
#   incomplete — no error, but the target package was NOT recorded
#   success    — target package recorded (or no target package expected)
if (!is.null(snap_error)) {
  snap_status <- "failure"
} else if (nzchar(target) && !target_recorded) {
  snap_status <- "incomplete"
} else {
  snap_status <- "success"
}

classify_snap_error <- function(msg) {
  if (is.null(msg)) return(NA_character_)
  m <- tolower(msg)
  if (grepl("cannot be validated", m))         "Bioconductor version validation failed"
  else if (grepl("biocversion", m))            "BiocVersion dependency not available"
  else if (grepl("biocmanager", m))            "BiocManager invoked but failed"
  else if (grepl("no internet|connection", m)) "Network connection error"
  else if (grepl("timeout", m))                "Timeout"
  else msg
}

cat("Snapshot status:", snap_status, "\n")

write_json(list(
  result                        = if (is.null(snap_error)) "ok" else paste0("error: ", snap_error),
  biocmanager_discovered        = biocmanager_found,
  biocversion_discovered        = biocversion_found,
  snapshot_status               = snap_status,
  snapshot_error_classification = classify_snap_error(snap_error),
  snapshot_warnings             = snap_warnings,
  renv_lock_written             = file.exists("renv.lock"),
  target_package                = target,
  target_package_recorded       = if (nzchar(target)) target_recorded else NA
), "snapshot_result.json")

cat("\nDone.\n")
