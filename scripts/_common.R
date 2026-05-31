# _common.R — shared boilerplate sourced by every step script.
# Provides the null-coalescing operator, the scenario/out_dir context derived
# from environment variables, and small helpers for the artifacts every step
# writes (session-info.txt, result.json).

`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

scenario <- Sys.getenv("SCENARIO", "unknown")
out_dir  <- file.path("/artifacts", scenario)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# sessionInfo() dump for the scenario.
write_session_info <- function() {
  sink(file.path(out_dir, "session-info.txt")); print(sessionInfo()); sink()
}

# Write a list as pretty JSON, treating NA as JSON null.
write_json <- function(obj, filename) {
  writeLines(
    jsonlite::toJSON(obj, auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(out_dir, filename)
  )
}
