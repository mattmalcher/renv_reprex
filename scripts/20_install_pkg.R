scenario <- Sys.getenv("SCENARIO", "unknown")
package  <- Sys.getenv("PACKAGE",  "metaRNASeq")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 20_install_pkg ===\n")
cat("Scenario:", scenario, "\n")
cat("Package:", package, "\n\n")

library(renv)

# Disable the global cache so the package is installed as a real directory,
# not a symlink to /root/.local/share/renv/cache. Without this, Phase 2
# (snapshot container) would see broken symlinks and treat the package as
# uninstalled — the global cache is not shared between Docker containers.
renv::settings$use.cache(FALSE)
cat("renv cache disabled\n")

cat("Installing", package, "via renv::install() (open network)...\n")
result <- tryCatch({
  renv::install(package)
  "success"
}, warning = function(w) {
  cat("WARNING:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("\nInstall result:", result, "\n")

# Write project.R so renv discovers the package as a project dependency
writeLines(paste0("library(", package, ")"), "project.R")
cat("Wrote project.R: library(", package, ")\n")

cat("\nDone.\n")
