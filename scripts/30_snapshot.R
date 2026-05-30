scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 30_snapshot ===\n")
cat("Scenario:", scenario, "\n\n")

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

cat("BiocManager in deps:", biocmanager_found, "\n")
cat("BiocVersion in deps:", biocversion_found, "\n\n")

# Run snapshot
cat("Running renv::snapshot()...\n")
snap_result <- tryCatch({
  renv::snapshot(prompt = FALSE)
  "success"
}, warning = function(w) {
  cat("WARNING:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("Snapshot result:", snap_result, "\n\n")

renv_lock_written <- file.exists("renv.lock")
if (renv_lock_written) {
  file.copy("renv.lock", file.path(out_dir, "renv.lock"), overwrite = TRUE)
  cat("renv.lock written.\n")
} else {
  cat("No renv.lock written.\n")
}

if (file.exists("renv/settings.json")) {
  file.copy("renv/settings.json", file.path(out_dir, "renv-settings.json"), overwrite = TRUE)
}

# Classify snapshot error
classify_snap_error <- function(result_str) {
  if (is.null(result_str) || result_str %in% c("success", "warning")) return(NA_character_)
  msg <- tolower(result_str)
  if (grepl("biocversion", msg))              "BiocVersion dependency not available"
  else if (grepl("cannot be validated", msg)) "Bioconductor version validation failed"
  else if (grepl("biocmanager", msg))         "BiocManager invoked but failed"
  else if (grepl("no internet|connection", msg)) "Network connection error"
  else if (grepl("timeout", msg))             "Timeout"
  else sub("^error:\\s*", "", result_str)
}

snap_status <- if (snap_result == "success") {
  "success"
} else if (snap_result == "warning") {
  "warning"
} else if (grepl("^error:", snap_result)) {
  "failure"
} else {
  snap_result
}

writeLines(
  toJSON(list(
    result                        = snap_result,
    biocmanager_discovered        = biocmanager_found,
    biocversion_discovered        = biocversion_found,
    snapshot_status               = snap_status,
    snapshot_error_classification = classify_snap_error(snap_result),
    renv_lock_written             = renv_lock_written
  ), auto_unbox = TRUE, pretty = TRUE, na = "null"),
  file.path(out_dir, "snapshot_result.json")
)

cat("\nDone.\n")
