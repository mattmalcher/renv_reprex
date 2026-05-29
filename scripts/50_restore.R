source("/scripts/bioc_detect.R")
scenario <- Sys.getenv("SCENARIO", "unknown")
subtest  <- Sys.getenv("SUBTEST", "")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

label <- if (nzchar(subtest)) paste0("50_restore (subtest: ", subtest, ")") else "50_restore"
cat("===", label, "===\n")
cat("Scenario:", scenario, "\n\n")

library(renv)

# Save pre-restore lockfile
if (file.exists("renv.lock")) {
  suffix <- if (nzchar(subtest)) paste0("pre_", subtest) else "pre_restore"
  file.copy("renv.lock", file.path(out_dir, paste0(suffix, "_lockfile.json")), overwrite = TRUE)
}

cat("Running renv::restore()...\n")
restore_result <- tryCatch({
  renv::restore(prompt = FALSE)
  "success"
}, warning = function(w) {
  cat("WARNING:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("Restore result:", restore_result, "\n\n")

# Check if lockfile changed (Bioc refs re-added) — accurate JSON-based detection
has_bioc_refs <- FALSE
if (file.exists("renv.lock")) {
  suffix <- if (nzchar(subtest)) paste0("post_", subtest) else "post_restore"
  file.copy("renv.lock", file.path(out_dir, paste0(suffix, "_lockfile.json")), overwrite = TRUE)
  has_bioc_refs <- lockfile_has_bioc_refs("renv.lock")
  cat("Lockfile has Bioconductor refs after restore:", has_bioc_refs, "\n")
}

writeLines(
  jsonlite::toJSON(list(
    result    = restore_result,
    bioc_refs = has_bioc_refs
  ), auto_unbox = TRUE, pretty = TRUE),
  file.path(out_dir, "restore_result.json")
)

cat("\nDone.\n")
