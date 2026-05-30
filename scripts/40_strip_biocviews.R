# 40_strip_biocviews.R — control for the minimal pair (scenario 5).
#
# Scenario 4 and scenario 5 install the SAME package (metaRNASeq) from the SAME
# repository (PPM/RSPM) under the SAME blocked-network snapshot. The only
# difference is this script: here we surgically remove the `biocViews` field
# from the installed package's DESCRIPTION before snapshot, isolating biocViews
# as the single independent variable. With biocViews gone, renv no longer infers
# Source = "Bioconductor" (snapshot.R:940) and snapshot succeeds.

package <- Sys.getenv("PACKAGE", "metaRNASeq")
cat("=== 40_strip_biocviews ===\n")
cat("Package:", package, "\n\n")

# Locate the installed package's DESCRIPTION inside the renv project library.
hits <- list.files("renv/library", pattern = "^DESCRIPTION$",
                   recursive = TRUE, full.names = TRUE)
desc <- grep(paste0("/", package, "/DESCRIPTION$"), hits, value = TRUE)

if (length(desc) != 1) {
  cat("ERROR: expected exactly one DESCRIPTION for", package,
      "but found", length(desc), "\n")
  print(hits)
  quit(status = 0)  # let snapshot run anyway so the artifact records the state
}

cat("DESCRIPTION:", desc, "\n")
dcf <- read.dcf(desc)
cat("biocViews before:", if ("biocViews" %in% colnames(dcf)) dcf[, "biocViews"] else "(absent)", "\n")

if ("biocViews" %in% colnames(dcf)) {
  dcf <- dcf[, colnames(dcf) != "biocViews", drop = FALSE]
  write.dcf(dcf, desc)
  cat("biocViews stripped.\n")
} else {
  cat("No biocViews field present — nothing to strip.\n")
}

# Verify
dcf2 <- read.dcf(desc)
cat("biocViews after:",
    if ("biocViews" %in% colnames(dcf2)) dcf2[, "biocViews"] else "(absent)", "\n")
cat("\nDone.\n")
