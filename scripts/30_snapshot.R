source("/scripts/bioc_detect.R")
scenario <- Sys.getenv("SCENARIO", "unknown")
subtest  <- Sys.getenv("SUBTEST", "")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

label <- if (nzchar(subtest)) paste0("30_snapshot (subtest: ", subtest, ")") else "30_snapshot"
cat("===", label, "===\n")
cat("Scenario:", scenario, "\n\n")

library(renv)

# Save pre-snapshot lockfile for diffing
if (file.exists("renv.lock")) {
  suffix <- if (nzchar(subtest)) paste0("pre_", subtest) else "pre_snapshot"
  file.copy("renv.lock", file.path(out_dir, paste0(suffix, "_lockfile.json")), overwrite = TRUE)
}

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

# Check for Bioconductor references in lockfile (accurate JSON-based detection)
has_bioc_refs <- FALSE
if (file.exists("renv.lock")) {
  suffix <- if (nzchar(subtest)) paste0("post_", subtest) else "post_snapshot"
  file.copy("renv.lock", file.path(out_dir, paste0(suffix, "_lockfile.json")), overwrite = TRUE)
  has_bioc_refs <- lockfile_has_bioc_refs("renv.lock")
  cat("Lockfile has Bioconductor refs:", has_bioc_refs, "\n")
} else {
  cat("No renv.lock found after snapshot.\n")
}

writeLines(
  jsonlite::toJSON(list(
    result        = snap_result,
    bioc_refs     = has_bioc_refs
  ), auto_unbox = TRUE, pretty = TRUE),
  file.path(out_dir, "snapshot_result.json")
)

cat("\nDone.\n")
