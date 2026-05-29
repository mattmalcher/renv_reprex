# renv / Bioconductor Debugging Harness

Reproduces and characterises the failure mode where a CRAN package (`recipes`) with a
`biocViews` DESCRIPTION field causes `renv` to inject Bioconductor repository references
into `renv.lock`, leading to failures in enterprise environments where Bioconductor is
unreachable.

## Quick start

```bash
./run_matrix.sh
```

This builds a Docker image (once) and runs all 8 scenarios. Artifacts land in `artifacts/`.

```
artifacts/
  A/   B/   C/   D/   E/   F/   G/   H/   # per-scenario logs and lockfiles
  summary.json                              # machine-readable results
  report.md                                 # Posit Support report
```

## Requirements

- Ubuntu 24.04 host
- Docker (see `install_docker.sh` if not yet installed)
- Internet access for Posit Package Manager (`packagemanager.posit.co`)

## Scenario matrix

| Scenario | Bioc blocked | Configuration |
|---|---|---|
| **A** | No | Baseline — open network |
| **B** | Yes | Default config — reproduces core failure |
| **C** | Yes | `options(renv.bioconductor.repos = character(0))` |
| **D** | Yes | `R_BIOC_VERSION=3.20` env var |
| **E** | Yes | `renv::settings$bioconductor.version("3.20")` |
| **F** | Yes | Non-empty stub `renv.bioconductor.repos` (PPM URL) |
| **G** | Yes | `BioC_mirror` + `BIOCONDUCTOR_CONFIG_FILE` stubs |
| **H** | Yes | Manual lockfile patch → isolate re-introduction source |

## Selective runs

```bash
./run_matrix.sh B C          # only Scenarios B and C
./run_matrix.sh --build-only # build image, do not run
```

## Key design choices

- **renv version**: 1.2.3 (pinned)
- **R version**: 4.4.2 (rocker/r-ver:4.4.2)
- **Bioconductor version**: 3.20 (aligned with R 4.4)
- **CRAN repo**: Posit Package Manager (Noble Linux binaries)
- **Bioc blocking**: Docker `--add-host` redirects to 127.0.0.1
- **Timeout**: 5 minutes per scenario
- **Isolation**: each scenario = fresh container, no shared renv cache

## Background

- `renv` checks `biocViews` in installed package DESCRIPTION metadata when inferring
  package source (related: `rstudio/renv#2128`)
- `renv#2149` fixed _empty_ `biocViews` fields but not non-empty ones
- `renv::settings$bioconductor.version()` persists to `renv/settings.json`
- Posit docs recommend `BioC_mirror`, `BIOCONDUCTOR_CONFIG_FILE`, and `R_BIOC_VERSION`
  for Bioconductor repo configuration in Workbench / Package Manager setups
