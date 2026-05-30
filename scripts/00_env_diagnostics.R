`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1 && is.na(x))) y else x
scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 00_env_diagnostics ===\n")
cat("Scenario:", scenario, "\n\n")

check_url_curl <- function(url, timeout_s = 10) {
  args   <- c("-s", "-o", "/dev/null", "-w", "%{http_code}",
              "--connect-timeout", as.character(timeout_s),
              "--max-time",        as.character(timeout_s), url)
  result <- tryCatch({
    code <- as.integer(system2("curl", args, stdout = TRUE, stderr = FALSE))
    if (!is.na(code) && code > 0) paste0("reachable (HTTP ", code, ")")
    else "blocked: no HTTP response"
  }, error = function(e) paste0("error: ", conditionMessage(e)))
  result
}

ppm_url  <- Sys.getenv("PPM_URL", "https://packagemanager.posit.co/cran/__linux__/noble/latest")
bioc_url <- "https://bioconductor.org"

cat("Checking PPM:", ppm_url, "\n")
ppm_status  <- check_url_curl(ppm_url)
cat("PPM status:", ppm_status, "\n\n")

cat("Checking Bioconductor:", bioc_url, "\n")
bioc_status <- check_url_curl(bioc_url)
cat("Bioconductor status:", bioc_status, "\n\n")

renv_ver <- tryCatch(as.character(packageVersion("renv")), error = function(e) "not installed")

info <- list(
  scenario               = scenario,
  r_version              = R.version$version.string,
  renv_version           = renv_ver,
  repos                  = getOption("repos"),
  BioC_mirror            = getOption("BioC_mirror"),
  BIOCONDUCTOR_CONFIG_FILE = getOption("BIOCONDUCTOR_CONFIG_FILE"),
  R_BIOC_VERSION         = Sys.getenv("R_BIOC_VERSION"),
  ppm_access             = grepl("^reachable", ppm_status),
  bioc_access            = grepl("^reachable", bioc_status),
  ppm_status             = ppm_status,
  bioc_status            = bioc_status
)

cat("repos:\n"); print(info$repos)
cat("\nrenv version:", renv_ver, "\n")
cat("PPM reachable:", info$ppm_access, "\n")
cat("Bioconductor reachable:", info$bioc_access, "\n")

sink(file.path(out_dir, "session-info.txt"))
print(sessionInfo())
sink()

jsonlite_ok <- requireNamespace("jsonlite", quietly = TRUE)
if (!jsonlite_ok) install.packages("jsonlite", repos = ppm_url, quiet = TRUE)

writeLines(
  jsonlite::toJSON(info, auto_unbox = TRUE, pretty = TRUE),
  file.path(out_dir, "env_diagnostics.json")
)
cat("Wrote env_diagnostics.json, session-info.txt\n\nDone.\n")
