source("/scripts/bioc_detect.R")
scenario <- Sys.getenv("SCENARIO", "unknown")
subtest  <- Sys.getenv("SUBTEST", "")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

label <- if (nzchar(subtest)) paste0("60_startup_check (subtest: ", subtest, ")") else "60_startup_check"
cat("===", label, "===\n")
cat("Scenario:", scenario, "\n\n")

# Save pre-startup lockfile
if (file.exists("renv.lock")) {
  suffix <- if (nzchar(subtest)) paste0("pre_", subtest) else "pre_startup"
  file.copy("renv.lock", file.path(out_dir, paste0(suffix, "_lockfile.json")), overwrite = TRUE)
}

cat("Simulating fresh R session startup (renv::load)...\n")
startup_result <- tryCatch({
  renv::load()
  "success"
}, warning = function(w) {
  cat("WARNING:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("Startup result:", startup_result, "\n\n")
cat("repos after load:", paste(getOption("repos"), collapse = ", "), "\n")
cat("BioC_mirror after load:", getOption("BioC_mirror") %||% "(unset)", "\n\n")

# Check if lockfile changed during startup (Bioc version inference) — accurate detection
has_bioc_refs <- FALSE
bioc_version_set <- FALSE
if (file.exists("renv.lock")) {
  suffix <- if (nzchar(subtest)) paste0("post_", subtest) else "post_startup"
  file.copy("renv.lock", file.path(out_dir, paste0(suffix, "_lockfile.json")), overwrite = TRUE)
  has_bioc_refs <- lockfile_has_bioc_refs("renv.lock")
  cat("Lockfile has Bioconductor refs after startup:", has_bioc_refs, "\n")
}

if (file.exists("renv/settings.json")) {
  settings_text <- paste(readLines("renv/settings.json"), collapse = "\n")
  bioc_version_set <- grepl("bioconductor.version", settings_text, ignore.case = TRUE)
  suffix <- if (nzchar(subtest)) paste0("post_", subtest) else "post_startup"
  file.copy("renv/settings.json", file.path(out_dir, paste0(suffix, "_settings.json")), overwrite = TRUE)
  cat("settings.json has bioconductor.version:", bioc_version_set, "\n")
}

writeLines(
  jsonlite::toJSON(list(
    result           = startup_result,
    bioc_refs        = has_bioc_refs,
    bioc_version_set = bioc_version_set,
    repos_after_load = as.list(getOption("repos")),
    BioC_mirror      = getOption("BioC_mirror") %||% NA
  ), auto_unbox = TRUE, pretty = TRUE),
  file.path(out_dir, "startup_result.json")
)

cat("\nDone.\n")
