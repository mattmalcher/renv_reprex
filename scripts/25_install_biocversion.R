scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 25_install_biocversion ===\n")
cat("Scenario:", scenario, "\n\n")

library(renv)

cat("Installing BiocVersion from Bioconductor to satisfy renv pre-flight check...\n")
cat("repos:", paste(getOption("repos"), collapse = ", "), "\n\n")

result <- tryCatch({
  renv::install("bioc::BiocVersion")
  "success"
}, warning = function(w) {
  cat("WARNING:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("\nInstall result:", result, "\n")
writeLines(result, file.path(out_dir, "install_biocversion_result.txt"))

biocver_desc <- system.file("DESCRIPTION", package = "BiocVersion")
if (nzchar(biocver_desc) && file.exists(biocver_desc)) {
  desc_lines <- readLines(biocver_desc)
  version_line <- grep("^Version:", desc_lines, value = TRUE)
  cat("BiocVersion installed:", version_line, "\n")
} else {
  cat("BiocVersion not found after install attempt.\n")
}

cat("\nDone.\n")
