# Scenario 10 — support workaround #1 (support thread): point
# renv.bioconductor.repos at a real, fast-resolving URL (not bioconductor.org) so
# the "probe" completes immediately instead of timing out. The URL need not be a
# valid Bioconductor mirror.
#
# Finding: like scenario 9, this overrides only renv_bioconductor_repos(). The
# independent version-validation call (renv_bioconductor_version ->
# BiocManager$version -> bioconductor.org/config.yaml) runs first and is
# unaffected, so snapshot still fails — the repos override is never even reached.
# A real-but-fast URL changes the failure from a timeout to an immediate error,
# but it does not let snapshot succeed.
options(renv.bioconductor.repos = c(
  BioCsoft = "http://127.0.0.1/bioc"   # resolves locally and fast; not bioconductor.org
))
if (file.exists("renv/activate.R")) source("renv/activate.R")
