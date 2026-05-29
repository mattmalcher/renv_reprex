# Scenario F: non-empty stub Bioconductor repos pointing at PPM root.
# Reachable URL that returns quickly but is not a real Bioc repo.
# Tests whether a non-empty option avoids the blank-URL timeout behaviour.
options(renv.bioconductor.repos = c(
  BioCsoft = "https://packagemanager.posit.co",
  BioCann  = "https://packagemanager.posit.co"
))

if (file.exists("renv/activate.R")) source("renv/activate.R")
