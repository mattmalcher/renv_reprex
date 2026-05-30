# renv biocViews → BiocVersion dependency repro

This repo demonstrates that renv treats a non-empty `biocViews` field in a DESCRIPTION
file as a Bioconductor signal and injects `BiocManager` + `BiocVersion` as implicit
dependencies. This can make `renv::snapshot()` fail in CRAN/PPM-only enterprise
environments where Bioconductor is unreachable, even when the user has not explicitly
depended on any Bioconductor package.

## Quick start

```bash
./run_matrix.sh
```

Builds a Docker image (once) and runs all 9 scenarios. Artifacts land in `artifacts/`.

```
artifacts/
  1/  2/  3/  4/  5/  6/  7/  8/  9/   # per-scenario logs and results
  summary.json                       # machine-readable results
  report.md                          # Posit Support report
```

## Requirements

- Docker
- Internet access for Posit Package Manager (`packagemanager.posit.co`)

## Selective runs

```bash
./run_matrix.sh 2 4 5 9    # only Scenarios 2, 4, 5, and 9
./run_matrix.sh --build-only
```

## The crux

In `renv/R/dependencies.R`, the function `renv_dependencies_discover_description()`:

```r
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

## Scenario matrix

| # | Description | Network | biocViews | Snapshot |
|---|-------------|---------|-----------|----------|
| **1** | Dependency discovery — no biocViews | open | absent | not run |
| **2** | Dependency discovery — with biocViews | open | present | not run |
| **3** | Real-world: recipes from CRAN/PPM | open | present | not run |
| **4** | Snapshot failure: `metaRNASeq` (biocViews present), Bioc blocked | Bioc blocked | present | **fails** |
| **5** | Snapshot control: `glue` (no biocViews), Bioc blocked | Bioc blocked | absent | **succeeds** |
| **6** | Workaround: `renv::settings$bioconductor.version("3.20")` | Bioc blocked | present | **warning** (partial) |
| **7** | Workaround: BiocVersion via PPM Bioconductor mirror | Bioc blocked | present | **fails** (renv still validates against bioconductor.org/config.yaml) |
| **8** | Workaround: stub `renv.bioconductor.repos` (PPM root) | Bioc blocked | present | **fails** (BiocVersion not installed) |
| **9** | Workaround: `renv.bioconductor.repos` → CRAN PPM URL | Bioc blocked | present | **fails** (BiocVersion not in CRAN repo; config.yaml check still hits bioconductor.org) |

## Packages used

Scenarios 1–2 (dependency discovery) use two minimal local fixtures under `fixtures/`
that differ only in the presence of `biocViews`:

- `fixtures/cranlike-no-biocviews/` — no `biocViews` field; no Bioconductor injection
- `fixtures/cranlike-with-biocviews/` — `biocViews: Software`; triggers BiocVersion injection

Scenarios 4–9 (snapshot / workaround) use real CRAN packages available from PPM:

- **`metaRNASeq`** (biocViews: `HighThroughputSequencing, RNAseq, DifferentialExpression`) —
  zero hard dependencies, no compiled code; the only zero-dep CRAN package on PPM with a
  non-empty `biocViews` field (see `scripts/find_cran_biocviews.R`)
- **`glue`** (scenario 5 control) — no `biocViews`; installs cleanly even with Bioconductor blocked

Scenarios 4/6/7/8/9 use a **two-phase Docker approach**: the package is installed via
`renv::install()` with open network (so renv tracks CRAN as the source), then snapshot
is run in a separate container with Bioconductor blocked.  Scenario 5 is single-phase
(blocked throughout) because `glue` triggers no Bioconductor checks during install.

## Key design choices

- **renv version**: 1.2.3 (pinned)
- **R version**: 4.4.2 (rocker/r-ver:4.4.2)
- **CRAN repo**: Posit Package Manager (Noble Linux binaries)
- **Bioc blocking**: Docker `--add-host` redirects bioconductor.org → 127.0.0.1
- **Timeout**: 5 minutes per scenario
- **Isolation**: each scenario = fresh container, no shared renv cache

## Artifacts per scenario

```
artifacts/<N>/
  stdout.log                # container stdout
  stderr.log                # container stderr
  result.json               # structured outcome
  discovered-dependencies.csv
  session-info.txt
  repos.txt
  renv-settings.json        # if renv settings were written
  renv.lock                 # if snapshot produced a lockfile
```

`result.json` fields: `scenario`, `ppm_reachable`, `bioconductor_reachable`,
`biocviews_present`, `biocmanager_discovered`, `biocversion_discovered`,
`snapshot_status`, `snapshot_error_classification`, `renv_lock_written`, `notes`.

## Workaround findings

All three `renv.bioconductor.repos`-style workarounds (scenarios 7, 8, 9) fail for the
same underlying reason: `renv` issues a version-validation HTTP request to
`bioconductor.org/config.yaml` unconditionally — it is **not** redirected by the
`renv.bioconductor.repos` option or by pointing `BioCsoft` at a mirror. With that host
blocked, version validation fails regardless of what repo URL is configured.

| Scenario | Approach | Result |
|----------|----------|--------|
| 6 | `renv::settings$bioconductor.version("3.20")` | **warning** — snapshot writes a partial lockfile; viable if packages are properly installed |
| 7 | `BioCsoft` repo → PPM Bioconductor mirror | **fails** — config.yaml check still hits bioconductor.org directly |
| 8 | `renv.bioconductor.repos` → PPM root URL | **fails** — BiocVersion not found; config.yaml check still hits bioconductor.org |
| 9 | `renv.bioconductor.repos` → CRAN PPM URL | **fails** — same as 8; CRAN repo has no BiocVersion and config.yaml check is not redirected |

The only approach that avoids a hard failure is scenario 6: pre-seeding
`bioconductor.version` so renv skips the config.yaml lookup. Combined with a reachable
Bioconductor mirror (PPM or internal) so `BiocVersion` can actually be installed, this
is the most viable workaround in a blocked-network environment.

The cleanest fix would be an renv change so that CRAN packages whose `biocViews` field
was set by the package author do not trigger Bioconductor-only dependency injection
when the user has not opted into Bioconductor — see
[renv#2149](https://github.com/rstudio/renv/issues/2149).

## Background

- renv issue [#2149](https://github.com/rstudio/renv/issues/2149) fixed *empty* biocViews
  but not non-empty ones
- The `recipes` package (CRAN) carries `biocViews: mixOmics` — a real-world trigger
- `BiocVersion` is Bioconductor-only and not mirrored by default on CRAN-only PPM
