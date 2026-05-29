You are working on an Ubuntu 24.04 machine with Docker already installed and working.

 

Your job is to build a fully reproducible, support-grade experiment harness that demonstrates a specific `renv` / Bioconductor failure mode and compares several workaround configurations.

 

## Goal

 

Produce a small repo that can be run end-to-end on an Ubuntu host and generates evidence showing:

 

1. `renv` can infer Bioconductor-ness from package DESCRIPTION metadata, including `biocViews`, when inferring package source. This matters because the triggering package in this case is a CRAN package (`recipes`) that appears to cause Bioconductor handling to activate. 

2. `renv` stores Bioconductor-related state in both the lockfile and project settings (`renv/settings.json`), and when `bioconductor.version` is unset it may infer a Bioconductor version dynamically. 

3. In a container where Posit Package Manager (PPM) is reachable but Bioconductor is not, some `renv` configurations fail or time out. 

4. The following configurations do and do not work, with clear evidence:

   - default behavior

   - `options(renv.bioconductor.repos = character(0))`

   - `Sys.setenv(R_BIOC_VERSION = "...")`

   - `renv::settings$bioconductor.version("...")`

   - `options(renv.bioconductor.repos = c(BioCsoft = "<stub URL>"))`

   - `options(BioC_mirror = "<stub URL>")`

   - `options(BIOCONDUCTOR_CONFIG_FILE = "<stub URL>/config.yaml")`

5. If the lockfile is manually patched to remove Bioconductor-related sections, determine exactly which action re-adds them:

   - session startup / project load

   - `renv::snapshot()`

   - `renv::restore()`

 

This must result in a reproducible experiment pack that can be sent to Posit Support.

 

## Important background facts

 

Use these as the behavioral assumptions you are trying to demonstrate and verify:

 

- `renv` uses installed package metadata to infer package source, and one of the fields it checks is `biocViews`. 

- `renv` documents that Bioconductor version can be stored as project-local state via `renv::settings$bioconductor.version(...)`, and these settings are persisted in `renv/settings.json`. 

- The upstream issue `rstudio/renv#2128` describes an enterprise scenario where packages with `biocViews` trigger Bioconductor handling, and `options(renv.bioconductor.repos = ...)` is discussed as the current workaround path. 

- `renv` later changed behavior to append, rather than prepend, Bioconductor repositories when installing, and added config for controlling the default `bioconductor` argument to `renv::init()`. 

- The separate `rstudio/renv#2149` fix was specifically about empty `biocViews` fields and does not cover the non-empty `biocViews` case. 

- Posit’s docs for Workbench / Package Manager document the use of `BioC_mirror`, `BIOCONDUCTOR_CONFIG_FILE`, and `R_BIOC_VERSION` in Bioconductor-related repository configuration.

 

## Non-goals

 

Do NOT:

- use Podman-specific features

- build a proxy, DNS server, or firewall setup unless simpler hostname blocking fails

- build a huge infra-heavy test harness

- “debug manually” without producing runnable artifacts

 

## Technical requirements

 

### Host assumptions

- Host OS: Ubuntu 24.04 LTS

- Container runtime: Docker

- Work root: create a local repo directory in the current working directory

 

### Repository / package assumptions

- Pin `renv` to version `1.2.3` by default

- Use `recipes` as the trigger package unless you discover that it does not reproduce the expected behavior in the chosen environment; if you must change package, document why

- Default to public Posit Package Manager (`https://packagemanager.posit.co`) unless overridden by environment variable

 

### Network setup

The container must:

- be able to access Posit Package Manager

- NOT be able to access Bioconductor

 

Prefer blocking Bioconductor using Docker runtime host overrides such as:

- `bioconductor.org`

- `www.bioconductor.org`

 

If logs show additional Bioconductor hostnames are used, add them and document them.

 

Do NOT use brittle IP-based blocking unless host override blocking proves insufficient.

 

## Deliverables

 

Create a repo with at least the following files:

 

- `Dockerfile`

- `README.md`

- `run_matrix.sh`

- `scripts/00_env_diagnostics.R`

- `scripts/10_init_project.R`

- `scripts/20_install_trigger_pkg.R`

- `scripts/30_snapshot.R`

- `scripts/40_patch_lockfile.R`

- `scripts/50_restore.R`

- `scripts/60_startup_check.R`

- `scripts/70_collect_artifacts.R`

- `artifacts/` directory (created by the scripts)

- optionally `templates/` for scenario-specific `.Rprofile` / `.Renviron` files

 

You may add helper shell scripts if needed.

 

## Required scenario matrix

 

Implement and run ALL of these scenarios.

 

### Scenario A: control / normal network

Purpose:

- establish baseline behavior when Bioconductor is reachable

 

Steps:

- configure R to use PPM as CRAN repo

- allow normal network access

- create minimal project

- install `renv` 1.2.3

- install `recipes`

- initialize `renv`

- snapshot

- record:

  - lockfile contents

  - `renv/settings.json`

  - repos / env diagnostics

  - startup behavior in a fresh R session

 

### Scenario B: blocked Bioconductor / default config

Purpose:

- reproduce the core enterprise failure mode

 

Steps:

- same as Scenario A, except block Bioconductor

- verify from inside container:

  - PPM fetch succeeds

  - Bioconductor fetch fails

- then run init / install / snapshot / startup / restore checks

 

### Scenario C: blocked Bioconductor + `options(renv.bioconductor.repos = character(0))`

Purpose:

- reproduce the user’s attempted workaround exactly

 

### Scenario D: blocked Bioconductor + `R_BIOC_VERSION` only

Purpose:

- test whether the env var alone changes startup / restore behavior

 

### Scenario E: blocked Bioconductor + `renv::settings$bioconductor.version("...")`

Purpose:

- test project-level pinned Bioconductor version

 

Choose a version aligned with the R version in the image and document the choice.

 

### Scenario F: blocked Bioconductor + non-empty stub `renv.bioconductor.repos`

Purpose:

- test the support suggestion that a real URL stub may avoid timeout behavior

 

Use a stub URL that resolves quickly on PPM. It does not need to be a real Bioconductor repo, but it must be non-empty and reachable.

 

### Scenario G: blocked Bioconductor + `BioC_mirror` and `BIOCONDUCTOR_CONFIG_FILE` stubs

Purpose:

- test the session-level BiocManager-oriented config suggested by support

 

### Scenario H: manual lockfile patch + isolate reintroduction source

Purpose:

- determine what re-adds Bioconductor references after manual removal

 

Procedure:

1. create lockfile in scenario where Bioc references appear

2. patch out Bioconductor-related sections manually

3. test independently:

   - startup only

   - snapshot only

   - restore only

4. record which one reintroduces Bioconductor-related content

 

## Data collection requirements

 

For every scenario, collect and save:

 

1. stdout/stderr logs

2. `sessionInfo()`

3. `getOption("repos")`

4. `getOption("BioC_mirror")`

5. `getOption("BIOCONDUCTOR_CONFIG_FILE")`

6. `Sys.getenv("R_BIOC_VERSION")`

7. current `renv` version

8. current `renv` config / settings values relevant to Bioconductor

9. `renv.lock`

10. `renv/settings.json` if present

11. installed `DESCRIPTION` for the trigger package (`recipes`)

12. network check output proving:

    - PPM reachable

    - Bioconductor blocked

13. a classification of each scenario outcome:

    - success

    - failure

    - timeout

    - Bioc refs present

    - Bioc refs absent

    - startup ok / startup failed

    - snapshot re-added refs yes/no

    - restore re-added refs yes/no

 

## Reporting requirements

 

Generate two summary outputs:

 

### 1. `artifacts/summary.json`

A machine-readable summary with one record per scenario. Include fields like:

- scenario_name

- ppm_access

- bioc_access

- lockfile_has_bioc_refs

- settings_has_bioc_version

- startup_status

- snapshot_status

- restore_status

- lockfile_reintroduced_by

- key_error_message

 

### 2. `artifacts/report.md`

A human-readable report intended for Posit Support. It must include:

- exact environment summary

- exact commands run

- scenario-by-scenario results

- diffs or excerpts showing lockfile changes

- diffs or excerpts showing settings changes

- conclusion section:

  - what reproduces

  - what does not

  - what action re-adds Bioc refs

  - which workaround(s) mitigate the problem

 

Keep this report concise but support-grade.

 

## Implementation style

 

Optimize for:

- simplicity

- determinism

- rerunnability

- obvious network blocking mechanism

- small number of moving parts

 

The top-level UX should be roughly:

1. build image

2. run one script

3. inspect `artifacts/`

 

## Build / run expectations

 

The repo should support something like:

 

```bash

./run_matrix.sh

```
