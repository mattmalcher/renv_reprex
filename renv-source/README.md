# renv 1.2.3 source reference

These files are fetched verbatim from renv 1.2.3 by `../fetch_renv_source.sh`.
To refresh or pin a different version:

```bash
../fetch_renv_source.sh          # re-fetch 1.2.3 (default)
../fetch_renv_source.sh 1.1.4    # fetch a different version
```

Source: https://github.com/rstudio/renv/tree/v1.2.3/R

## Key locations

### `R/dependencies.R` — the biocViews trigger

**`renv_dependencies_discover_description()`** (line 575)  
Called for every DESCRIPTION file during dependency discovery.

The relevant block is at **lines 599–608**:

```r
# if this is a bioconductor package, add their implicit dependencies
# guard against packages which have an empty biocViews field
# https://github.com/rstudio/renv/issues/2149
if (nzchar(dcf[["biocViews"]] %||% "")) {
  data[[length(data) + 1L]] <- renv_dependencies_list(
    source   = path,
    packages = c(renv_bioconductor_manager(), "BiocVersion")
  )
  names(data)[[length(data)]] <- "Bioconductor"
}
```

Any non-empty `biocViews` value — regardless of whether the package is actually from
Bioconductor — injects `BiocManager` + `BiocVersion` as implicit dependencies of type
`"Bioconductor"`. On R ≥ 3.5, `renv_bioconductor_manager()` returns `"BiocManager"`.

### `R/bioconductor.R` — version resolution and the network call

**`renv_bioconductor_version()`** (line 108)  
Determines the Bioconductor version for the project. Called during `renv::snapshot()`
when any Bioconductor dependency has been discovered.

Lookup order:
1. `options(renv.bioconductor.version)` — not normally set
2. `settings$bioconductor.version(project)` — the scenario 6 workaround
3. `BiocVersion` package (if installed)
4. `renv_bioconductor_init()` → installs `BiocManager`, then calls `BiocManager$version()`

`BiocManager$version()` makes an HTTP request to `bioconductor.org/config.yaml` to
determine the current release. If that host is blocked, it throws:

```
invalid version specification 'unknown version: Bioconductor version cannot be
validated; no internet connection?'
```

**`renv_bioconductor_repos()`** (line 150)  
Builds the Bioconductor repository list. Calls `renv_bioconductor_version()` internally.
Note: the `renv.bioconductor.repos` option short-circuits this function (line 153–155),
but `BiocManager$version()` can still be reached via other code paths during snapshot.
