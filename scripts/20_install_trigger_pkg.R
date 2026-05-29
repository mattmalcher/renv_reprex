scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 20_install_trigger_pkg ===\n")
cat("Scenario:", scenario, "\n\n")

library(renv)

cat("Installing recipes...\n")
cat("repos:", paste(getOption("repos"), collapse = ", "), "\n\n")

result <- tryCatch({
  renv::install("recipes")
  "success"
}, warning = function(w) {
  cat("WARNING during install:", conditionMessage(w), "\n")
  "warning"
}, error = function(e) {
  cat("ERROR during install:", conditionMessage(e), "\n")
  paste0("error: ", conditionMessage(e))
})

cat("\nInstall result:", result, "\n")
writeLines(result, file.path(out_dir, "install_result.txt"))

# Save recipes DESCRIPTION if installed
recipes_desc <- system.file("DESCRIPTION", package = "recipes")
if (nzchar(recipes_desc) && file.exists(recipes_desc)) {
  file.copy(recipes_desc, file.path(out_dir, "recipes_DESCRIPTION.txt"), overwrite = TRUE)
  cat("\nrecipes DESCRIPTION saved.\n")

  desc_lines <- readLines(recipes_desc)
  bioc_views <- grep("^biocViews", desc_lines, value = TRUE, ignore.case = TRUE)
  if (length(bioc_views) > 0) {
    cat("biocViews field found:", bioc_views, "\n")
  } else {
    cat("No biocViews field in recipes DESCRIPTION.\n")
  }
} else {
  cat("recipes not installed (skipping DESCRIPTION copy)\n")
}

# Create a minimal project script so implicit snapshot picks up recipes.
# This mirrors the realistic scenario: a user who installs recipes to use in their project.
cat("\nWriting project.R with library(recipes)...\n")
writeLines("library(recipes)", "project.R")
cat("project.R written.\n")

cat("\nDone.\n")
