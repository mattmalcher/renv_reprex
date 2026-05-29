# renv / Bioconductor Failure Mode Report

Generated: 2026-05-29 13:25:51 UTC

---

## Environment

- **R version**: R version 4.4.2 (2024-10-31)
- **renv version**: 1.2.3
- **OS**: Ubuntu 24.04 (Noble), Docker container
- **PPM URL**: https://packagemanager.posit.co/cran/__linux__/noble/latest
- **Trigger package**: recipes
- **Bioconductor version tested**: 3.20

---

## Scenario Results

| Scenario | Bioc blocked | PPM ok | Bioc refs in lock | Startup | Snapshot | Restore | Re-introduced by |
|---|---|---|---|---|---|---|---|
| **A** Control (open network) | No | Yes | No | success | failure | success | — |
| **B** Blocked, default config | Yes | Yes | No | success | failure | success | — |
| **C** Blocked + renv.bioconductor.repos=character(0) | Yes | Yes | No | success | failure | success | — |
| **D** Blocked + R_BIOC_VERSION env var | Yes | Yes | No | success | failure | success | — |
| **E** Blocked + renv::settings$bioconductor.version() | Yes | Yes | No | success | warning | success | — |
| **F** Blocked + non-empty stub repos | Yes | Yes | No | success | failure | success | — |
| **G** Blocked + BioC_mirror + BIOCONDUCTOR_CONFIG_FILE | Yes | Yes | No | success | failure | success | — |
| **H** Blocked + manual lockfile patch | Yes | Yes | No | success | failure | success | none |

---

## Scenario Details

### Scenario A: Control (open network)

**PPM reachable**: Yes
**Bioconductor reachable**: Yes

**Lockfile**: No Bioconductor section or repos.

**Key error**: `ERROR: aborting snapshot due to pre-flight validation failure `

### Scenario B: Blocked, default config

**PPM reachable**: Yes
**Bioconductor reachable**: No

**Lockfile**: No Bioconductor section or repos.

**Key error**: `ERROR: invalid version specification ‘unknown version: Bioconductor version cannot be validated; no internet connection?`

### Scenario C: Blocked + renv.bioconductor.repos=character(0)

**PPM reachable**: Yes
**Bioconductor reachable**: No

**Lockfile**: No Bioconductor section or repos.

**Key error**: `ERROR: aborting snapshot due to pre-flight validation failure `

### Scenario D: Blocked + R_BIOC_VERSION env var

**PPM reachable**: Yes
**Bioconductor reachable**: No

**Lockfile**: No Bioconductor section or repos.

**Key error**: `ERROR: aborting snapshot due to pre-flight validation failure `

### Scenario E: Blocked + renv::settings$bioconductor.version()

**PPM reachable**: Yes
**Bioconductor reachable**: No

**Lockfile**: No Bioconductor section or repos.

### Scenario F: Blocked + non-empty stub repos

**PPM reachable**: Yes
**Bioconductor reachable**: No

**Lockfile**: No Bioconductor section or repos.

**Key error**: `ERROR: aborting snapshot due to pre-flight validation failure `

### Scenario G: Blocked + BioC_mirror + BIOCONDUCTOR_CONFIG_FILE

**PPM reachable**: Yes
**Bioconductor reachable**: No

**Lockfile**: No Bioconductor section or repos.

**Key error**: `ERROR: invalid version specification ‘unknown version: Bioconductor version map cannot be validated; is it misconfigured?`

### Scenario H: Blocked + manual lockfile patch

**PPM reachable**: Yes
**Bioconductor reachable**: No

**Lockfile**: No Bioconductor section or repos.

**Key error**: `ERROR: invalid version specification ‘unknown version: Bioconductor version cannot be validated; no internet connection?`

**Lockfile re-introduced by**: none

**Bioc lines before patch:**
```
        "URL": "https://bioconductor.org/packages/3.20/bioc"
        "URL": "https://bioconductor.org/packages/3.20/data/annotation"
        "URL": "https://bioconductor.org/packages/3.20/data/experiment"
        "URL": "https://bioconductor.org/packages/3.20/workflows"
      "Config/testthat/start-first": "bioconductor,python,install,restore,snapshot,retrieve,remotes",
  "Bioconductor": {
```
**Bioc lines after patch:**
```
      "Config/testthat/start-first": "bioconductor,python,install,restore,snapshot,retrieve,remotes",
```

---

## Conclusion

### Root cause

The `recipes` CRAN package includes a `biocViews: mixOmics` field in its DESCRIPTION.
renv 1.2.3 treats any installed package with `biocViews` as a Bioconductor package.
This triggers two distinct failure paths in `renv::snapshot()`:

1. **Open network (Scenario A):** renv's pre-flight check requires `BiocVersion` to be
   installed before snapshotting any project that contains a biocViews package.
   `BiocVersion` is only available from Bioconductor, not from PPM.
   Error: `aborting snapshot due to pre-flight validation failure`

2. **Bioc-blocked network (Scenario B):** renv calls BiocManager to validate/resolve
   the Bioconductor version before snapshot. With bioconductor.org unreachable,
   BiocManager cannot validate and snapshot aborts.
   Error: `Bioconductor version cannot be validated; no internet connection?`

Neither failure requires the user to have explicitly opted into Bioconductor.
Simply having `recipes` in `project.R` is sufficient to trigger it.

### Snapshot failure by scenario

- **Hard failure** (error): Scenarios B, C, D, F, G, H
- **Soft failure** (warning, incomplete lockfile): Scenarios E

### Workaround analysis

| Scenario | Approach | Snapshot outcome | Key error |
|---|---|---|---|
| B | None (default) | failure | BiocManager version validation fails (network) |
| C | `renv.bioconductor.repos=character(0)` | failure | BiocVersion preflight still runs |
| D | `R_BIOC_VERSION=3.20` env var | failure | Bypasses version check but renv still fetches Bioc repo indices |
| E | `settings$bioconductor.version('3.20')` | warning | BiocManager not invoked for version; snapshot writes but excludes recipes |
| F | Stub bioc repo URLs | failure | BiocVersion preflight still runs |
| G | `BioC_mirror` + `BIOCONDUCTOR_CONFIG_FILE` | failure | Config file parsed but version map validation fails |
| H | Manual lockfile patch | failure | Patch works but next snapshot call fails again |

### What action re-adds Bioc refs after manual lockfile patch

- Scenario H result: **none** — startup and restore succeed with a patched lockfile, but snapshot always fails again (BiocManager is invoked on every snapshot call).

### Recommended mitigation

No single option tested here fully prevents renv from invoking Bioconductor machinery
when `recipes` (or any package with `biocViews`) is in the project. Options to explore
with Posit Support:

- **Install BiocVersion from PPM** if PPM mirrors it — satisfies the preflight check
  without reaching bioconductor.org.
- **`renv::settings$bioconductor.version('3.20')`** (Scenario E) reduces the failure
  from hard error to warning and avoids the network call, but the lockfile is incomplete.
- **Exclude the `biocViews`-bearing package from snapshot** and manage it separately.
- **File an renv issue**: the current behaviour of requiring BiocVersion for any package
  that has `biocViews` (even CRAN packages installed from PPM) appears unintentional.

