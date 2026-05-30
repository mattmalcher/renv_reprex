# Scenario 8: Stub renv.bioconductor.repos pointing at PPM root.
# Tests the Posit-recommended workaround of setting a non-empty
# renv.bioconductor.repos option to a reachable (but non-Bioconductor) URL.
options(renv.bioconductor.repos = c(
  BioCsoft = "https://packagemanager.posit.co",
  BioCann  = "https://packagemanager.posit.co"
))
if (file.exists("renv/activate.R")) source("renv/activate.R")
