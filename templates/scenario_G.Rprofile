# Scenario G: BiocManager-oriented options suggested by Posit Support.
# BioC_mirror: redirect to PPM (will fail for Bioc content but resolves fast).
# BIOCONDUCTOR_CONFIG_FILE: point to a local stub config.yaml bundled in image.
options(
  BioC_mirror              = "https://packagemanager.posit.co",
  BIOCONDUCTOR_CONFIG_FILE = "/templates/bioc_config_stub.yaml"
)

if (file.exists("renv/activate.R")) source("renv/activate.R")
