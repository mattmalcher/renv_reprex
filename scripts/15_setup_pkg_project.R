# 15_setup_pkg_project.R — Path A setup (scenario 8).
#
# Path A: the PROJECT ITSELF is a package whose DESCRIPTION carries a non-empty
# biocViews field. Here renv::dependencies() runs over the project DESCRIPTION
# and genuinely *discovers* BiocManager + BiocVersion as implicit dependencies
# (renv_dependencies_discover_description, dependencies.R:602). Snapshot then
# fails trying to obtain BiocVersion with Bioconductor blocked.
#
# This is the distinct counterpart to Path B (scenario 4), where the project
# merely *depends on* an installed CRAN package that happens to have biocViews
# and BiocVersion is never discovered as a dependency at all.

fixture <- Sys.getenv("FIXTURE", "cranlike-with-biocviews")
src     <- file.path("/fixtures", fixture)

cat("=== 15_setup_pkg_project ===\n")
cat("Fixture (used as the project package):", fixture, "\n\n")

# Copy the fixture package contents into the project root so /project IS the package.
for (item in list.files(src, full.names = TRUE)) {
  file.copy(item, ".", recursive = TRUE, overwrite = TRUE)
}
cat("Project now contains:\n")
print(list.files(".", recursive = TRUE))

cat("\n--- project DESCRIPTION ---\n")
cat(paste(readLines("DESCRIPTION"), collapse = "\n"), "\n\n")

library(renv)
cat("renv::init(bare = TRUE)  # do not auto-install deps; isolate the failure to snapshot\n\n")
renv::init(bare = TRUE, restart = FALSE)

cat("\nDone.\n")
