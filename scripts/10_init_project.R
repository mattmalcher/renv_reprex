scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 10_init_project ===\n")
cat("Scenario:", scenario, "\n\n")

library(renv)

cat("renv version:", as.character(packageVersion("renv")), "\n")
cat("Working directory:", getwd(), "\n\n")

# No explicit bioconductor arg — we want renv to behave exactly as a user who
# installs recipes without knowing it has biocViews. The Bioc refs appear
# automatically via snapshot, not because anyone opted in.
cat("renv::init()\n\n")

renv::init(restart = FALSE)

cat("\n--- post-init lockfile ---\n")
if (file.exists("renv.lock")) {
  lock_text <- readLines("renv.lock")
  cat(paste(lock_text, collapse = "\n"), "\n")
  file.copy("renv.lock", file.path(out_dir, "post_init_lockfile.json"), overwrite = TRUE)
} else {
  cat("(no renv.lock created)\n")
}

# Scenario E: pin Bioconductor version after init so it's written to settings.json
if (scenario == "E") {
  cat("Scenario E: setting bioconductor.version = 3.20\n")
  tryCatch(
    renv::settings$bioconductor.version("3.20"),
    error = function(e) cat("WARNING: could not set bioconductor.version:", e$message, "\n")
  )
}

cat("\n--- renv/settings.json ---\n")
if (file.exists("renv/settings.json")) {
  settings_text <- readLines("renv/settings.json")
  cat(paste(settings_text, collapse = "\n"), "\n")
  file.copy("renv/settings.json", file.path(out_dir, "post_init_settings.json"), overwrite = TRUE)
}

cat("\nDone.\n")
