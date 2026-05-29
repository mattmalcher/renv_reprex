source("/scripts/bioc_detect.R")
scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 40_patch_lockfile ===\n")
cat("Scenario:", scenario, "\n\n")

if (!file.exists("renv.lock")) {
  stop("renv.lock not found — cannot patch")
}

original <- paste(readLines("renv.lock"), collapse = "\n")
lock <- jsonlite::fromJSON(original, simplifyVector = FALSE)

bioc_refs_before <- lockfile_has_bioc_refs("renv.lock")
cat("Bioc refs before patch:", bioc_refs_before, "\n")

if (!is.null(lock$Bioconductor)) {
  cat("Removing lock$Bioconductor section\n")
  lock$Bioconductor <- NULL
}

if (!is.null(lock$R$Repositories)) {
  repos <- lock$R$Repositories
  bioc_repos <- vapply(repos, function(r) {
    grepl("bioconductor\\.org", r$URL %||% "", ignore.case = TRUE)
  }, logical(1))
  if (any(bioc_repos)) {
    cat("Removing", sum(bioc_repos), "Bioconductor repo(s) from R$Repositories\n")
    lock$R$Repositories <- repos[!bioc_repos]
  } else {
    cat("No Bioconductor repos found in R$Repositories\n")
  }
}

patched <- jsonlite::toJSON(lock, auto_unbox = TRUE, pretty = TRUE)
writeLines(patched, "renv.lock")

bioc_refs_after <- lockfile_has_bioc_refs("renv.lock")
cat("Bioc refs after patch:", bioc_refs_after, "\n")

orig_lines    <- strsplit(original, "\n")[[1]]
patched_lines <- strsplit(patched,  "\n")[[1]]
writeLines(orig_lines,    file.path(out_dir, "lockfile_before_patch.json"))
writeLines(patched_lines, file.path(out_dir, "lockfile_after_patch.json"))

writeLines(
  jsonlite::toJSON(list(
    bioc_refs_before = bioc_refs_before,
    bioc_refs_after  = bioc_refs_after
  ), auto_unbox = TRUE, pretty = TRUE),
  file.path(out_dir, "patch_result.json")
)

cat("\nDone.\n")
