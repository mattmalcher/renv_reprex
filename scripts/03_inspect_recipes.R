scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

`%||%` <- function(x, y) if (is.null(x)) y else x

cat("=== 03_inspect_recipes ===\n")
cat("Scenario:", scenario, "\n\n")

library(jsonlite)

ppm_url <- Sys.getenv("PPM_URL", "https://packagemanager.posit.co/cran/__linux__/noble/latest")

cat("Installing recipes from PPM...\n")
cat("repos:", ppm_url, "\n\n")

install_result <- tryCatch({
  install.packages("recipes", repos = ppm_url, quiet = FALSE)
  "success"
}, warning = function(w) {
  cat("WARNING during install:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR during install:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("\nInstall result:", install_result, "\n\n")

desc <- tryCatch(packageDescription("recipes"), error = function(e) NULL)

biocviews_present <- FALSE
biocviews_value   <- ""
repository_value  <- ""

if (!is.null(desc)) {
  biocviews_value   <- desc$biocViews %||% ""
  repository_value  <- desc$Repository %||% ""
  biocviews_present <- nzchar(biocviews_value)

  cat("--- recipes metadata ---\n")
  cat("Package:   ", desc$Package    %||% "unknown", "\n")
  cat("Version:   ", desc$Version    %||% "unknown", "\n")
  cat("Repository:", repository_value, "\n")
  cat("biocViews: ", if (biocviews_present) biocviews_value else "(absent)", "\n\n")

  # Save raw DESCRIPTION
  desc_path <- system.file("DESCRIPTION", package = "recipes")
  if (file.exists(desc_path)) {
    file.copy(desc_path, file.path(out_dir, "recipes_DESCRIPTION.txt"), overwrite = TRUE)
    cat("Saved recipes DESCRIPTION to artifacts.\n")
  }

} else {
  cat("ERROR: recipes not installed or packageDescription() failed.\n")
}

notes <- paste0(
  "recipes repository: '", repository_value, "'. ",
  "biocViews: '", biocviews_value, "'. ",
  "Key point: recipes is installed from CRAN/PPM but has non-empty biocViews."
)

sink(file.path(out_dir, "session-info.txt")); print(sessionInfo()); sink()

result <- list(
  scenario                      = scenario,
  ppm_reachable                 = TRUE,
  bioconductor_reachable        = NA,
  biocviews_present             = biocviews_present,
  biocmanager_discovered        = NA,
  biocversion_discovered        = NA,
  snapshot_status               = "not_run",
  snapshot_error_classification = NA,
  renv_lock_written             = FALSE,
  notes                         = notes
)
writeLines(toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
           file.path(out_dir, "result.json"))
cat("Wrote result.json\n\nDone.\n")
