source("/scripts/bioc_detect.R")
scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 31_snapshot_force ===\n")
cat("Scenario:", scenario, "\n\n")
cat("Constructing synthetic lockfile with Bioconductor refs.\n")
cat("This simulates the lockfile a developer on an open network would produce\n")
cat("when recipes' biocViews causes renv to inject Bioc repos.\n\n")

if (!file.exists("renv.lock")) {
  stop("renv.lock not found — run renv::init() first")
}

file.copy("renv.lock", file.path(out_dir, "pre_force_snapshot_lockfile.json"), overwrite = TRUE)

lock <- jsonlite::fromJSON("renv.lock", simplifyVector = FALSE)

# Inject Bioconductor repos matching what renv adds for Bioc 3.20 + R 4.4
lock$R$Repositories <- c(
  lock$R$Repositories,
  list(list(Name = "BioCsoft", URL = "https://bioconductor.org/packages/3.20/bioc")),
  list(list(Name = "BioCann",  URL = "https://bioconductor.org/packages/3.20/data/annotation")),
  list(list(Name = "BioCexp",  URL = "https://bioconductor.org/packages/3.20/data/experiment")),
  list(list(Name = "BioCworkflows", URL = "https://bioconductor.org/packages/3.20/workflows"))
)

# Inject Bioconductor version section
lock$Bioconductor <- list(Version = "3.20")

patched <- jsonlite::toJSON(lock, auto_unbox = TRUE, pretty = TRUE)
writeLines(patched, "renv.lock")

has_bioc_refs <- lockfile_has_bioc_refs("renv.lock")
cat("Bioconductor refs present after injection:", has_bioc_refs, "\n")
cat("Bioconductor section:", jsonlite::toJSON(lock$Bioconductor, auto_unbox = TRUE), "\n")
cat("Repo count:", length(lock$R$Repositories), "\n")

file.copy("renv.lock", file.path(out_dir, "post_force_snapshot_lockfile.json"), overwrite = TRUE)

cat("\nDone.\n")
