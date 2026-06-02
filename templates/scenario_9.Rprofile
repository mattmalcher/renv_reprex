# Scenario 9 — initial customer attempt (support thread): options(renv.bioconductor.repos = character(0)).
#
# Intent: tell renv "there are no Bioconductor repositories" so it stops reaching
# bioconductor.org. In renv 1.2.3 this overrides ONLY renv_bioconductor_repos()
# (bioconductor.R:153 — it returns early for any non-NULL value, including
# character(0)). It does NOT touch snapshot's prior call to
# renv_bioconductor_version() (snapshot.R:397 -> bioconductor.R:108), which still
# reaches bioconductor.org/config.yaml via BiocManager$version() to validate the
# Bioconductor release. With that host blocked, snapshot still fails — exactly the
# "they get re-added / it still times out" outcome the customer reported.
options(renv.bioconductor.repos = character(0))
if (file.exists("renv/activate.R")) source("renv/activate.R")
