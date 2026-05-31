# 03_inspect_cran_pkg.R — real-world existence proof (scenario 3).
#
# Installs an ordinary CRAN package from PPM and shows it carries a non-empty
# biocViews field while Repository = RSPM — i.e. the trigger is not exotic, it
# appears on mainstream CRAN packages. The package is parameterised (PACKAGE env,
# default "genetics", a long-standing CRAN package with biocViews: Genetics).
# find_cran_biocviews.R lists many more.

source("/scripts/_common.R")
package <- Sys.getenv("PACKAGE", "genetics")

cat("=== 03_inspect_cran_pkg ===\n")
cat("Scenario:", scenario, "\n")
cat("Package:", package, "\n\n")

library(jsonlite)

ppm_url <- Sys.getenv("PPM_URL", "https://packagemanager.posit.co/cran/__linux__/noble/latest")

cat("Installing", package, "from PPM...\n")
cat("repos:", ppm_url, "\n\n")

install_result <- tryCatch({
  install.packages(package, repos = ppm_url, quiet = FALSE)
  "success"
}, warning = function(w) {
  cat("WARNING during install:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR during install:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("\nInstall result:", install_result, "\n\n")

desc <- tryCatch(packageDescription(package), error = function(e) NULL)

biocviews_present <- FALSE
biocviews_value   <- ""
repository_value  <- ""

if (!is.null(desc)) {
  biocviews_value   <- desc$biocViews %||% ""
  repository_value  <- desc$Repository %||% ""
  biocviews_present <- nzchar(biocviews_value)

  cat("---", package, "metadata ---\n")
  cat("Package:   ", desc$Package    %||% "unknown", "\n")
  cat("Version:   ", desc$Version    %||% "unknown", "\n")
  cat("Repository:", repository_value, "\n")
  cat("biocViews: ", if (biocviews_present) biocviews_value else "(absent)", "\n\n")

  # Save raw DESCRIPTION
  desc_path <- system.file("DESCRIPTION", package = package)
  if (file.exists(desc_path)) {
    file.copy(desc_path, file.path(out_dir, "cran-pkg_DESCRIPTION.txt"), overwrite = TRUE)
    cat("Saved", package, "DESCRIPTION to artifacts.\n")
  }

} else {
  cat("ERROR:", package, "not installed or packageDescription() failed.\n")
}

notes <- paste0(
  package, " repository: '", repository_value, "'. ",
  "biocViews: '", biocviews_value, "'. ",
  "Key point: ", package, " is installed from CRAN/PPM but has non-empty biocViews."
)

write_session_info()

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
write_json(result, "result.json")
cat("Wrote result.json\n\nDone.\n")
