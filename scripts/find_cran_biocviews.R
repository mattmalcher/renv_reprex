#!/usr/bin/env Rscript
# find_cran_biocviews.R
#
# Finds CRAN packages (available from Posit Package Manager) that have a
# non-empty biocViews field in their DESCRIPTION.
#
# The PACKAGES index does not carry biocViews, so we:
#   1. Query PPM for all available package names.
#   2. Filter to bio-keyword names as a fast first pass.
#   3. Look up full metadata for each candidate via the crandb JSON API.
#
# Usage (inside the project Docker image, or any R >= 4.0 with jsonlite):
#   Rscript scripts/find_cran_biocviews.R
#
# Results are printed to stdout. Re-running is safe — no state is written.

PPM_URL  <- "https://packagemanager.posit.co/cran/__linux__/noble/latest"
CRANDB   <- "https://crandb.r-pkg.org"

`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

options(repos = c(CRAN = PPM_URL))

cat("Step 1: fetching PPM CRAN package list...\n")
all_pkgs <- rownames(available.packages())
cat("  Total packages on PPM CRAN binary:", length(all_pkgs), "\n")

# Fast first pass: packages with bio-domain keywords in their name
bio_pattern <- paste0(
  "bio|gene|seq|omics|omic|cell|RNA|DNA|protein|microarray|",
  "genome|transcr|metabol|proteom|pathway|annot|variant|",
  "flow|cytom|amplicon|phylo|align|blast|fasta|fastq"
)
candidates <- all_pkgs[grepl(bio_pattern, all_pkgs, ignore.case = TRUE, perl = TRUE)]
cat("  Bio-keyword packages (first-pass candidates):", length(candidates), "\n\n")

cat("Step 2: querying crandb for biocViews field...\n\n")

check_crandb <- function(pkg) {
  url <- sprintf("%s/%s", CRANDB, pkg)
  tryCatch({
    meta <- jsonlite::fromJSON(url, simplifyVector = FALSE)
    bv   <- meta$biocViews
    if (is.null(bv) || !nzchar(bv)) return(NULL)
    n_imports <- length(meta$Imports %||% list())
    n_depends <- length(setdiff(names(meta$Depends %||% list()), "R"))
    list(
      package    = pkg,
      version    = meta$Version   %||% NA_character_,
      biocViews  = bv,
      n_hard_deps = n_imports + n_depends,
      imports    = paste(names(meta$Imports  %||% list()), collapse = ", "),
      depends    = paste(setdiff(names(meta$Depends %||% list()), "R"), collapse = ", ")
    )
  }, error = function(e) NULL)
}

hits <- Filter(Negate(is.null), lapply(candidates, check_crandb))
hits <- hits[order(sapply(hits, `[[`, "n_hard_deps"))]

cat(sprintf("Found %d package(s) with non-empty biocViews on PPM CRAN:\n\n", length(hits)))

for (h in hits) {
  cat(sprintf("Package:    %s %s\n", h$package, h$version))
  cat(sprintf("biocViews:  %s\n", h$biocViews))
  cat(sprintf("Hard deps:  %d  (Imports: %s | Depends: %s)\n",
              h$n_hard_deps,
              if (nzchar(h$imports)) h$imports else "(none)",
              if (nzchar(h$depends)) h$depends else "(none)"))
  cat("\n")
}

if (length(hits) == 0) cat("(none found)\n\n")

cat("Done.\n")
