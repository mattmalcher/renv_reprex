# renv 1.2.3 source reference

These files are fetched verbatim from renv 1.2.3 by `../fetch_renv_source.sh`.
To refresh or pin a different version:

```bash
../fetch_renv_source.sh          # re-fetch 1.2.3 (default)
../fetch_renv_source.sh 1.1.4    # fetch a different version
```

Source: https://github.com/rstudio/renv/tree/v1.2.3/R

## Two distinct biocViews-triggered code paths

A non-empty `biocViews` field bites in **two independent places**. The repro treats
them separately:

- **Path A — dependency discovery** (`dependencies.R`). When `renv::dependencies()`
  scans a DESCRIPTION with `biocViews`, it *injects* `BiocManager` + `BiocVersion` as
  implicit dependencies. This fires when the project itself is a package with
  `biocViews` (scenario 8) or for the fixtures in scenarios 1–2.
- **Path B — snapshot source inference** (`snapshot.R`). When `renv::snapshot()` records
  an *installed* package whose DESCRIPTION has `biocViews`, it infers
  `Source = "Bioconductor"` — even for a package installed from CRAN/PPM with
  `Repository: RSPM` — and then validates the Bioconductor version over the network
  (scenarios 4, 6, 7). `BiocVersion` is **not** discovered as a dependency here.

Both paths converge on `bioconductor.R`'s `renv_bioconductor_version()` network call.

## Key locations

### `R/dependencies.R` — Path A: the biocViews dependency injection

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

### `R/snapshot.R` — Path B: snapshot source inference + validation

**`renv_snapshot_description_source()`** (line 928)  
Infers the `Source` field recorded for each installed package. At **lines 938–941**:

```r
# packages from Bioconductor are normally tagged with a 'biocViews' entry;
# use that to infer a Bioconductor source
if (nzchar(dcf[["biocViews"]] %||% ""))
  return(list(Source = "Bioconductor"))
```

This runs *before* the repository checks below it, so a CRAN/PPM package whose
DESCRIPTION carries `biocViews` is recorded with `Source = "Bioconductor"` even though
its `Repository` is `RSPM`.

**`renv_snapshot_validate_bioconductor()`** (line 368)  
Pre-flight snapshot validation. If any record has `Source == "Bioconductor"`
(lines 374–376) it resolves the Bioconductor version (lines 395–397):

```r
version <-
  lockfile$Bioconductor$Version %||%
  renv_bioconductor_version(project = project)
```

→ this is the call into `bioconductor.R` that hits the network and fails when
`bioconductor.org` is blocked. Note `BiocVersion` is never *discovered* as a
dependency on this path; the failure is purely version validation.

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
