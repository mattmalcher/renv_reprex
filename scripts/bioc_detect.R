# Shared helper: accurate Bioconductor reference detection in renv lockfiles.
# A lockfile "has Bioc refs" only when:
#   - There is a top-level "Bioconductor" key in the JSON, OR
#   - Any repository URL contains "bioconductor.org"
# This avoids false positives from the word "bioconductor" appearing in renv's
# own embedded DESCRIPTION metadata (Suggests: BiocManager, etc.).

lockfile_has_bioc_refs <- function(lockfile_path) {
  if (!file.exists(lockfile_path)) return(FALSE)
  tryCatch({
    lock <- jsonlite::fromJSON(lockfile_path, simplifyVector = FALSE)
    has_bioc_section <- !is.null(lock$Bioconductor)
    has_bioc_repos   <- any(vapply(
      lock$R$Repositories %||% list(),
      function(r) grepl("bioconductor\\.org", r$URL %||% "", ignore.case = TRUE),
      logical(1)
    ))
    has_bioc_section || has_bioc_repos
  }, error = function(e) {
    # Fallback if JSON parse fails
    grepl("bioconductor\\.org", paste(readLines(lockfile_path, warn = FALSE), collapse = "\n"), ignore.case = TRUE)
  })
}

`%||%` <- function(x, y) if (is.null(x)) y else x
