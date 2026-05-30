# renv biocViews → BiocVersion dependency repro

This repo demonstrates that renv treats a non-empty `biocViews` field in a DESCRIPTION
file as a Bioconductor signal and injects `BiocManager` + `BiocVersion` as implicit
dependencies. This can make `renv::snapshot()` fail in CRAN/PPM-only enterprise
environments where Bioconductor is unreachable, even when the user has not explicitly
depended on any Bioconductor package.

**Environment used in this run**

- R 4.4.2 (rocker/r-ver:4.4.2), renv 1.2.3 (pinned), Ubuntu 24.04 (Noble)
- CRAN repo: Posit Package Manager (Noble Linux binaries)
- Bioconductor blocking: Docker `--add-host` redirects `bioconductor.org → 127.0.0.1`

---

## Quick start

```bash
./run_matrix.sh
```

Builds a Docker image (once) and runs all 7 scenarios. Artifacts land in `artifacts/`.

```
artifacts/
  summary.json          # machine-readable results for all scenarios
  1/ … 7/               # per-scenario logs and results
```

```bash
./run_matrix.sh 2 4 5    # run specific scenarios
./run_matrix.sh --build-only
./reset.sh               # wipe artifacts for a clean re-run
./reset.sh --rmi         # also remove the Docker image
./fetch_renv_source.sh   # refresh renv-source/ from GitHub (default: 1.2.3)
```

**Prerequisites:** Docker, internet access to `packagemanager.posit.co`.

---

## The crux

In `renv/R/dependencies.R`, `renv_dependencies_discover_description()` (line 575):

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

Any non-empty `biocViews` value — including on a CRAN-installed package — causes renv
to add `BiocManager` (available from CRAN/PPM) and `BiocVersion` (Bioconductor-only)
as implicit dependencies. In a CRAN-only environment, `BiocVersion` cannot be resolved
and `renv::snapshot()` fails.

See `renv-source/R/dependencies.R` lines 599–608 for the exact source.

---

## Call stack

```
renv::snapshot()
  └─ discovers installed packages, scans each DESCRIPTION
       └─ renv_dependencies_discover_description()        [dependencies.R:575]
            └─ biocViews non-empty → injects BiocManager + BiocVersion
  └─ resolves Bioconductor version (needed to assign BiocVersion to a repo)
       └─ renv_bioconductor_version()                     [bioconductor.R:108]
            └─ settings$bioconductor.version() → NULL (not set)
            └─ BiocVersion not installed
            └─ renv_bioconductor_init() → installs BiocManager
            └─ BiocManager$version()
                 └─ HTTP GET bioconductor.org/config.yaml
                      └─ FAIL: connection refused (host blocked)
                         └─ "Bioconductor version cannot be validated; no internet connection?"
```

The `bioconductor.version` project setting (scenario 6 workaround) short-circuits this
by returning early at `settings$bioconductor.version(project = project)`.

See `renv-source/R/bioconductor.R` lines 108–145 for the version resolution path.

---

## Scenario matrix

| # | Description | Network | biocViews | Snapshot |
|---|-------------|---------|-----------|----------|
| **1** | Dependency discovery — no biocViews | open | absent | not run |
| **2** | Dependency discovery — with biocViews | open | present | not run |
| **3** | Real-world: `recipes` from CRAN/PPM | open | present | not run |
| **4** | Snapshot failure: `metaRNASeq`, Bioc blocked | Bioc blocked | present | **fails** |
| **5** | Snapshot control: `glue` (no biocViews), Bioc blocked | Bioc blocked | absent | **succeeds** |
| **6** | Workaround: `renv::settings$bioconductor.version("3.20")` | Bioc blocked | present | **warning** (partial) |
| **7** | Workaround: BiocVersion via PPM Bioconductor mirror | Bioc blocked | present | **fails** |

---

## 1. Minimal fixture proof (scenarios 1 & 2)

Two minimal local packages under `fixtures/` differ only in the presence of `biocViews`.
Scenarios 1 and 2 run `renv::dependencies()` directly on each DESCRIPTION.

| Fixture | biocViews field | BiocManager discovered | BiocVersion discovered |
|---------|----------------|------------------------|------------------------|
| `cranlike-no-biocviews` | absent | No | No |
| `cranlike-with-biocviews` | `biocViews: Software` | **Yes** | **Yes** |

The discovered-dependencies CSV for scenario 2 shows both packages with `Type = "Bioconductor"`:

```
"Type","Source","Package","Require","Version","Dev"
"Imports",".../cranlike-with-biocviews/DESCRIPTION","stats","","",FALSE
"Bioconductor",".../cranlike-with-biocviews/DESCRIPTION","BiocManager","","",FALSE
"Bioconductor",".../cranlike-with-biocviews/DESCRIPTION","BiocVersion","","",FALSE
```

Evidence: `artifacts/1/discovered-dependencies.csv` and `artifacts/2/discovered-dependencies.csv`.

---

## 2. Real-package proof (scenario 3)

Scenario 3 installs `recipes` from Posit Package Manager and inspects its DESCRIPTION.
`recipes` has `biocViews: mixOmics` but is installed from CRAN/PPM, not from Bioconductor.

```r
packageDescription("recipes")[c("Package", "Version", "Repository", "biocViews")]
```

Its `biocViews` metadata is sufficient to trigger renv's Bioconductor dependency injection.
`metaRNASeq` (`biocViews: HighThroughputSequencing, RNAseq, DifferentialExpression`) is
used in scenarios 4–7 as the snapshot trigger because it has zero compiled dependencies
and installs quickly from PPM; `find_cran_biocviews.R` was used to identify it.

Evidence: `artifacts/3/recipes_DESCRIPTION.txt` and `artifacts/3/output.log`.

---

## 3. Snapshot proof (scenarios 4 & 5)

Scenarios 4 and 5 use identical network configuration (Bioconductor blocked, PPM
reachable). The only difference is which package is installed.

| Scenario | Package | biocViews | Bioc blocked | Snapshot status |
|----------|---------|-----------|--------------|-----------------|
| **4** | `metaRNASeq` | present | Yes | **FAILURE** |
| **5** | `glue` | absent | Yes | **SUCCESS** |

**Scenario 5 is the key control**: the same blocked network does not prevent snapshot
when there is no `biocViews` trigger. The failure in scenario 4 is caused entirely by
renv's implicit `BiocVersion` dependency injection.

**Exact error from scenario 4:**

```
ERROR: invalid version specification 'unknown version: Bioconductor version cannot be
validated; no internet connection?
    See #troubleshooting section in vignette'
```

Evidence: `artifacts/4/output.log`, `artifacts/4/result.json`, `artifacts/5/result.json`.

Scenarios 4, 6, and 7 use a two-phase Docker approach: the package is installed via
`renv::install()` with an open network (so renv records CRAN as the source), then
snapshot runs in a second container with Bioconductor blocked.

---

## 4. Workaround analysis (scenarios 6 & 7)

### Scenario 6 — `renv::settings$bioconductor.version("3.20")`

Pre-seeding the Bioconductor version bypasses the `BiocManager$version()` network call
(see call stack above). Snapshot emits a warning but does not hard-fail. The lockfile is
written. When the project is properly installed (not from local source), this is a viable
workaround.

**Status: WARNING — snapshot writes a partial lockfile.**

### Scenario 7 — PPM Bioconductor mirror as `BioCsoft` repo

Configuring `options(repos = c(CRAN = ..., BioCsoft = <PPM Bioconductor mirror>))` makes
`BiocVersion` potentially available via PPM, but snapshot still fails with the same
version validation error as scenario 4. The `BioCsoft` repo setting does not redirect
`BiocManager$version()`'s call to `bioconductor.org/config.yaml` — that request is made
unconditionally through BiocManager, not through renv's repo configuration.

**Status: FAILURE — Bioconductor version validation still hits bioconductor.org.**

### Summary

| Scenario | Approach | Result |
|----------|----------|--------|
| 6 | `renv::settings$bioconductor.version("3.20")` | **warning** — lockfile written |
| 7 | `BioCsoft` → PPM Bioconductor mirror | **fails** — `config.yaml` hit unconditionally |

Evidence: `artifacts/6/result.json`, `artifacts/6/output.log`, `artifacts/7/result.json`.

---

## 5. Conclusion

This issue is not that Bioconductor repositories appear in the lockfile. The blocker is
earlier: renv's dependency discovery converts a `biocViews` DESCRIPTION field into an
implicit dependency on `BiocVersion`. Since `BiocVersion` is not available from
CRAN-only PPM and Bioconductor is blocked, `renv::snapshot()` cannot complete for a
project that otherwise uses only CRAN packages.

**Recommended path forward:**

- **Viable workaround**: combine `renv::settings$bioconductor.version("3.20")` with a
  reachable Bioconductor mirror (PPM or internal) so renv can both skip the `config.yaml`
  lookup and actually install `BiocVersion` if needed.
- **Upstream fix**: renv should not treat CRAN-installed packages with a `biocViews`
  field as Bioconductor packages for the purpose of dependency injection when the user
  has not opted into Bioconductor. See [renv#2149](https://github.com/rstudio/renv/issues/2149),
  which fixed the empty-biocViews case but not the non-empty case.

---

## Key design choices

- **renv version**: 1.2.3 (pinned via `remotes::install_version`)
- **R version**: 4.4.2 (rocker/r-ver:4.4.2)
- **CRAN repo**: Posit Package Manager (Noble Linux binaries)
- **Bioc blocking**: Docker `--add-host` redirects `bioconductor.org → 127.0.0.1`
- **Timeout**: 5 minutes per scenario
- **Isolation**: each scenario = fresh container, no shared renv cache
- **Two-phase scenarios (4, 6, 7)**: package installed with open network so renv records
  CRAN as the source; snapshot run in a separate container with Bioconductor blocked

---

## Artifacts per scenario

```
artifacts/<N>/
  output.log                   # combined stdout + stderr from the container
  result.json                  # structured outcome
  discovered-dependencies.csv  # renv::dependencies() output (scenarios 1, 2, 4–7)
  session-info.txt             # R sessionInfo()
  renv.lock                    # lockfile if snapshot produced one (scenarios 4–7)
  renv-settings.json           # renv project settings if written (scenarios 4–7)
  recipes_DESCRIPTION.txt      # package metadata (scenario 3 only)
```

`result.json` fields: `scenario`, `ppm_reachable`, `bioconductor_reachable`,
`biocviews_present`, `biocmanager_discovered`, `biocversion_discovered`,
`snapshot_status`, `snapshot_error_classification`, `renv_lock_written`.

---

## Background

- renv issue [#2149](https://github.com/rstudio/renv/issues/2149) fixed *empty* biocViews
  but not non-empty ones
- `recipes` (CRAN) carries `biocViews: mixOmics` — a real-world trigger
- `BiocVersion` is Bioconductor-only and is not mirrored by default on CRAN-only PPM
