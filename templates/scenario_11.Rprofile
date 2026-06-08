# Scenario 11 — full short-circuit combo (support thread follow-up).
#
# Three levers together DO stop renv reaching bioconductor.org at snapshot time:
#   * R_BIOC_VERSION pins the Bioconductor release so BiocManager$version()
#     resolves offline (no config.yaml fetch);
#   * BIOCONDUCTOR_ONLINE_VERSION_DIAGNOSIS = FALSE disables BiocManager's online
#     version diagnosis;
#   * renv.bioconductor.repos = character(0) short-circuits renv_bioconductor_repos().
#
# Result: snapshot() COMPLETES and records metaRNASeq (Source = "Bioconductor").
# But the project is now permanently OUT OF SYNC: metaRNASeq's biocViews makes
# renv treat BiocManager + BiocVersion as project dependencies
# (dependencies.R:602), and they can never be installed from CRAN/PPM. So
# renv::status() reports BiocManager and BiocVersion as inconsistent and
# renv::activate() flags the project out of sync on every startup — the symptom
# the customer described after the network timeouts were silenced.
#
# (R_BIOC_VERSION must be set before BiocManager loads, so it lives here in the
# .Rprofile rather than being passed in at the operation.)
Sys.setenv(
  R_BIOC_VERSION = "3.20",                       # aligns with R 4.4 / Bioconductor 3.20
  BIOCONDUCTOR_ONLINE_VERSION_DIAGNOSIS = "FALSE"
)
options(
  renv.bioconductor.repos = character(0),
  BIOCONDUCTOR_ONLINE_VERSION_DIAGNOSIS = FALSE  # set as an option as well in the report
)
if (file.exists("renv/activate.R")) source("renv/activate.R")
