# renv biocViews → BiocVersion Dependency Failure Report

Generated: 2026-05-30 08:56:04 UTC

---

## 1. Executive Summary

A non-empty `biocViews` field in a package DESCRIPTION file causes `renv` dependency
discovery to inject `BiocManager` and `BiocVersion` as implicit dependencies.
In a CRAN/PPM-only environment where Bioconductor is blocked, `BiocVersion` cannot
be resolved, so `renv::snapshot()` cannot complete — even when the user has not
explicitly depended on any Bioconductor package.

**Environment**

- R version: R version 4.4.2 (2024-10-31)
- renv version: 1.2.3
- OS: Ubuntu 24.04 (Noble), Docker container
- CRAN repo: Posit Package Manager (Noble Linux binaries)
- Bioconductor blocking: Docker `--add-host` redirects bioconductor.org → 127.0.0.1

---

## 2. Code-Path Evidence

The trigger is in `renv/R/dependencies.R`, function `renv_dependencies_discover_description()`:

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

- This branch fires on **any** non-empty `biocViews` value.
- On R ≥ 4.0, `renv_bioconductor_manager()` returns `"BiocManager"`.
- `BiocManager` is available from CRAN/PPM. **`BiocVersion` is not** — it is a
  Bioconductor-only package.
- Therefore any project whose dependency graph includes a package with non-empty
  `biocViews` will fail `renv::snapshot()` on a CRAN-only, Bioconductor-blocked network.

---

## 3. Minimal Fixture Proof

Two tiny local packages were created — identical except for the `biocViews` field.
Scenarios 1 and 2 run `renv::dependencies()` on each DESCRIPTION directly.

| Fixture | biocViews field | BiocManager discovered | BiocVersion discovered |
|---------|----------------|------------------------|------------------------|
| `cranlike-no-biocviews` | absent | No | No |
| `cranlike-with-biocviews` | `biocViews: Software` | **Yes** | **Yes** |

Scenario 1 expected: no `BiocManager`, no `BiocVersion`.
Scenario 2 expected: `BiocManager` and `BiocVersion` present, type = `Bioconductor`.

---

## 4. Real-Package Proof: `recipes`

Scenario 3 installs `recipes` from Posit Package Manager (CRAN) and inspects its metadata.

```r
packageDescription("recipes")[c("Package", "Version", "Repository", "biocViews")]
```

- `biocViews`: `mixOmics`

Key point: `recipes` is installed from CRAN/PPM, not from Bioconductor.
Its `biocViews` metadata is enough to trigger renv's Bioconductor dependency injection.

---

## 5. Snapshot Proof Under Blocked Bioconductor

Scenarios 4 and 5 use identical network configuration (Bioconductor blocked, PPM reachable).
The only difference is which fixture package is installed.

| Scenario | Fixture | biocViews | Bioc blocked | Snapshot status | Error |
|----------|---------|-----------|--------------|-----------------|-------|
| 4 | `cranlike-with-biocviews` | present | Yes | **FAILURE** | Bioconductor version validation failed |
| 5 | `cranlike-no-biocviews` | absent | Yes | **SUCCESS** | — |

Scenario 5 is the key control: the same blocked network does **not** prevent snapshot
when there is no `biocViews` trigger. The failure in Scenario 4 is caused purely by
renv's implicit `BiocVersion` dependency injection.

---

## 6. Workaround Analysis

| Scenario | Approach | Snapshot status | Error / Notes |
|----------|---------|-----------------|---------------|
| 4 | None — baseline failure | **FAILURE** | Bioconductor version validation failed |
| 6 | `renv::settings$bioconductor.version('3.20')` | **WARNING** |  |
| 7 | PPM Bioconductor mirror (`BioCsoft` repo pointing to PPM) | **FAILURE** | Bioconductor version validation failed |
| 8 | `options(renv.bioconductor.repos = c(...))` — PPM root | **FAILURE** | aborting snapshot due to pre-flight validation failure |
| 9 | `options(renv.bioconductor.repos = c(...))` — CRAN PPM URL | **FAILURE** | aborting snapshot due to pre-flight validation failure |

---

## 7. Conclusion

This issue is not primarily that Bioconductor repositories appear in the lockfile.
The blocker is earlier: dependency discovery converts `biocViews` metadata into an
implicit dependency on `BiocVersion`. Since `BiocVersion` is not available from
CRAN-only PPM and Bioconductor is blocked, `renv::snapshot()` cannot complete for
a project that otherwise uses only CRAN packages.

**Workaround findings from this test run:**

- **Scenario 6 — `renv::settings$bioconductor.version('3.20')`**: snapshot emits
  a warning (BiocManager not available, bioconductor.org unreachable) but does not
  hard-fail. The lockfile is written; however packages installed outside renv's
  tracking (e.g. local source) are excluded. When used with a properly installed
  project this may be a viable workaround.
- **Scenario 7 — PPM Bioconductor mirror as `BioCsoft` repo**: snapshot FAILS with
  the same Bioconductor version validation error as scenario 4. renv still queries
  `bioconductor.org/config.yaml` for version validation even when a mirror is configured;
  this call is not redirected to the PPM mirror. Setting `BioCsoft` alone is insufficient.
- **Scenario 8 — stub `renv.bioconductor.repos`**: snapshot FAILS with pre-flight
  validation failure (BiocVersion not installed). Pointing repos at an address that
  does not serve BiocVersion does not help.

**Recommended fixes:**

- **Combine `bioconductor.version` + a reachable Bioconductor mirror** (PPM or internal)
  so renv can both determine the version and install `BiocVersion` without bioconductor.org.
- **File an renv issue** requesting that CRAN packages with `biocViews` not trigger
  Bioconductor-only dependency injection when the user has not opted into Bioconductor.

---

## Appendix: Full Scenario Results

| # | Description | PPM | Bioc blocked | biocViews | Snap status |
|---|-------------|-----|-------------|-----------|-------------|
| 1 | Discovery — no biocViews | Yes | N/A | absent | not_run |
| 2 | Discovery — with biocViews | Yes | N/A | present | not_run |
| 3 | Real-world: recipes from CRAN/PPM | Yes | N/A | present | not_run |
| 4 | Snapshot failure: with biocViews, Bioc blocked | Yes | Yes | present | failure |
| 5 | Snapshot control: no biocViews, Bioc blocked | Yes | Yes | absent | success |
| 6 | Workaround: renv::settings$bioconductor.version('3.20') | Yes | Yes | present | warning |
| 7 | Workaround: BiocVersion via PPM Bioconductor mirror | Yes | Yes | present | failure |
| 8 | Workaround: stub renv.bioconductor.repos (PPM root) | Yes | Yes | present | failure |
| 9 | Workaround: renv.bioconductor.repos pointing at CRAN PPM URL | Yes | Yes | present | failure |

