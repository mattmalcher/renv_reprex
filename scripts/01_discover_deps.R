source("/scripts/_common.R")
fixture <- Sys.getenv("FIXTURE", "cranlike-with-biocviews")

cat("=== 01_discover_deps ===\n")
cat("Scenario:", scenario, "\n")
cat("Fixture:", fixture, "\n\n")

fixture_desc <- file.path("/fixtures", fixture, "DESCRIPTION")
cat("Running renv::dependencies() on:", fixture_desc, "\n\n")

library(renv)
library(jsonlite)

# Check biocViews in fixture DESCRIPTION
desc_lines      <- readLines(fixture_desc)
biocviews_line  <- grep("^biocViews", desc_lines, value = TRUE, ignore.case = TRUE)
biocviews_value <- if (length(biocviews_line) > 0) trimws(sub("^biocViews:\\s*", "", biocviews_line[[1]], ignore.case = TRUE)) else ""
biocviews_present <- nzchar(biocviews_value)
cat("biocViews field:", if (biocviews_present) biocviews_value else "(absent)", "\n\n")

# Run dependency discovery
deps <- tryCatch(
  renv::dependencies(fixture_desc, progress = FALSE, errors = "ignored"),
  error = function(e) {
    cat("ERROR from renv::dependencies():", conditionMessage(e), "\n")
    NULL
  }
)

if (!is.null(deps) && nrow(deps) > 0) {
  cat("Discovered dependencies:\n")
  print(deps)
  write.csv(deps, file.path(out_dir, "discovered-dependencies.csv"), row.names = FALSE)
  cat("\nWrote discovered-dependencies.csv\n")
} else {
  cat("No dependencies discovered.\n")
  write.csv(
    data.frame(Source = character(), Package = character(), Require = character(),
               Version = character(), Dev = logical()),
    file.path(out_dir, "discovered-dependencies.csv"),
    row.names = FALSE
  )
}

biocmanager_found <- !is.null(deps) && "BiocManager" %in% deps$Package
biocversion_found <- !is.null(deps) && "BiocVersion" %in% deps$Package
bioc_type_found   <- !is.null(deps) && any(grepl("Bioconductor", deps$Type %||% ""), na.rm = TRUE)

cat("\nBiocManager discovered:", biocmanager_found, "\n")
cat("BiocVersion discovered:", biocversion_found, "\n")
cat("Bioconductor dependency type present:", bioc_type_found, "\n")

# Session info and repos
write_session_info()

result <- list(
  scenario                    = scenario,
  ppm_reachable               = TRUE,
  bioconductor_reachable      = NA,
  biocviews_present           = biocviews_present,
  biocmanager_discovered      = biocmanager_found,
  biocversion_discovered      = biocversion_found,
  snapshot_status             = "not_run",
  snapshot_error_classification = NA,
  renv_lock_written           = FALSE,
  notes = paste0("Dependency discovery only. Fixture: ", fixture,
                 ". biocViews value: '", biocviews_value, "'.")
)
write_json(result, "result.json")
cat("Wrote result.json\n\nDone.\n")
