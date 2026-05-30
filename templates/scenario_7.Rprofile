# Scenario 7: Add PPM Bioconductor mirror so BiocVersion can be resolved
# without direct access to bioconductor.org.
# bioconductor.org is still blocked via --add-host; PPM is reachable.
local({
  ppm_bioc <- Sys.getenv(
    "PPM_BIOC_URL",
    "https://packagemanager.posit.co/bioconductor/__linux__/noble/latest"
  )
  options(repos = c(
    CRAN     = Sys.getenv("PPM_URL", "https://packagemanager.posit.co/cran/__linux__/noble/latest"),
    BioCsoft = ppm_bioc
  ))
})
if (file.exists("renv/activate.R")) source("renv/activate.R")
