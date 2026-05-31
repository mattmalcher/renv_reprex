# 35_capture_source_inference.R — Path B evidence, captured surgically.
#
# Scenario 4's headline is "renv infers Source = Bioconductor for a CRAN/PPM
# package because of its biocViews field." Under the blocked network of phase 2
# that inference is never visible in an artifact: snapshot aborts during
# pre-flight validation before any record is written. And even with the network
# OPEN a full snapshot can't complete here — metaRNASeq's biocViews makes renv
# treat BiocVersion as a required (but uninstalled) dependency, so snapshot
# aborts pre-flight regardless of network.
#
# So we call the misclassifying function directly. renv_snapshot_description_source()
# (snapshot.R:924, the `biocViews` branch at :940) is exactly what snapshot uses to
# decide the Source recorded for each installed package. We hand it the installed
# metaRNASeq DESCRIPTION (Repository = RSPM) and observe it return
# Source = "Bioconductor". That return value IS the bug, captured in isolation.

source("/scripts/_common.R")
package <- Sys.getenv("PACKAGE", "metaRNASeq")

cat("=== 35_capture_source_inference ===\n")
cat("Package:", package, "\n\n")

library(renv)
library(jsonlite)

desc_path <- tryCatch(
  file.path(find.package(package), "DESCRIPTION"),
  error = function(e) ""
)

source_value     <- NA_character_
repository_value <- NA_character_
biocviews_value  <- NA_character_

if (nzchar(desc_path) && file.exists(desc_path)) {
  # Read the DESCRIPTION the way renv does internally, then feed it to the very
  # function snapshot uses to infer a package's Source.
  dcf <- renv:::renv_description_read(path = desc_path)
  inferred <- renv:::renv_snapshot_description_source(dcf)

  source_value     <- inferred$Source        %||% NA_character_
  repository_value <- dcf[["Repository"]]     %||% NA_character_
  biocviews_value  <- dcf[["biocViews"]]      %||% NA_character_

  cat("Installed", package, "DESCRIPTION:\n")
  cat("  Repository:", repository_value, "\n")
  cat("  biocViews: ", biocviews_value, "\n")
  cat("renv_snapshot_description_source() inferred Source:", source_value, "\n\n")

  write_json(list(
    Package    = package,
    Source     = source_value,
    Repository = repository_value,
    biocViews  = biocviews_value
  ), "lock-source-inference.json")
  cat("Saved lock-source-inference.json\n")
} else {
  cat("WARNING: could not locate installed", package, "DESCRIPTION.\n")
}

# Hand the captured Source to 70_collect_artifacts (runs in phase 2).
write_json(list(
  metarnaseq_source_open_network     = source_value,
  metarnaseq_repository_open_network = repository_value
), "source_inference.json")

cat("\nDone.\n")
