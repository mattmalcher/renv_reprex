You are updating an existing repo called renv_reprex.

 

The current repo has a scenario matrix and report focused partly on Bioconductor references being written into renv.lock. That is no longer the main point.

 

The main blocker we need to demonstrate is narrower and more important:

 

A CRAN package with a non-empty biocViews field can cause renv dependency discovery to inject BiocManager and BiocVersion as implicit dependencies. In a CRAN/PPM-only environment where Bioconductor is unreachable and BiocVersion is not mirrored, renv::snapshot() cannot complete, even though the user did not explicitly depend on Bioconductor packages.

 

Please update the repo to focus on this crux and remove irrelevant / distracting lockfile-contamination framing.

 

## Core finding to demonstrate

 

In renv/R/dependencies.R, the function renv_dependencies_discover_description() contains this logic:

 

```r

# if this is a bioconductor package, add their implicit dependencies

# guard against packages which have an empty biocViews field

# https://github.com/rstudio/renv/issues/2149

if (nzchar(dcf[["biocViews"]] %||% "")) {

  data[[length(data) + 1L]] <- renv_dependencies_list(

    source = path,

    packages = c(renv_bioconductor_manager(), "BiocVersion")

  )

  names(data)[[length(data)]] <- "Bioconductor"

}

This is the key code path.

For R >= 3.5.0, renv_bioconductor_manager() resolves to "BiocManager", so a non-empty biocViews field causes dependency discovery to add:

    BiocManager
    BiocVersion

BiocManager is available from CRAN / PPM.

BiocVersion is not available from CRAN-only PPM; it is a Bioconductor package.

Therefore, in a restricted enterprise environment where:

    Posit Package Manager CRAN repo is reachable;
    Bioconductor is blocked;
    no Bioconductor mirror is configured in PPM;

renv::snapshot() can fail solely because a CRAN package contains non-empty biocViews metadata.

Important framing change

Do not lead with “lockfile contamination”.

Lockfile contamination / Bioconductor repos appearing in renv.lock is still useful context, but it is not the blocker we want to prove.

The blocker is:

renv turns biocViews metadata into an implicit dependency on BiocVersion, and BiocVersion cannot be resolved in a CRAN-only, Bioconductor-blocked environment.

Update README, report, scenario names, and conclusions accordingly.

What to remove or de-emphasise

Remove or strongly de-emphasise:

    claims that the primary issue is Bioconductor refs being re-added to renv.lock;
    the complicated “which action reintroduces lockfile refs?” focus;
    scenarios whose only purpose is lockfile patching;
    any conclusion that says startup / restore lockfile pollution is the primary failure.

Keep lockfile inspection only as secondary diagnostics.

New desired repo purpose

The repo should answer these questions:

    Does a DESCRIPTION file with non-empty biocViews cause renv::dependencies() to report BiocManager and BiocVersion?
    Does this happen even if the package/project otherwise depends only on CRAN packages?
    Does renv::snapshot() fail in a CRAN/PPM-only environment when Bioconductor is blocked because BiocVersion cannot be resolved?
    Does the same project succeed if either:
        biocViews is absent / empty; or
        BiocVersion is made available; or
        Bioconductor version / repositories are configured in a way that avoids the failing resolution path?
    Which workaround, if any, actually makes snapshot complete without public Bioconductor access?

Stronger experimental design

The current repo uses recipes as the trigger package. Keep that if useful, but add a minimal local package fixture because it makes the crux easier to prove.

Create two tiny local package directories under something like:

fixtures/

  cranlike-no-biocviews/

    DESCRIPTION

    R/dummy.R

 

  cranlike-with-biocviews/

    DESCRIPTION

    R/dummy.R

The two fixture packages should be identical except:

cranlike-no-biocviews/DESCRIPTION

Should have normal CRAN-like metadata and dependencies only on base / stats / utils or another trivial CRAN dependency.

It must not contain biocViews.

cranlike-with-biocviews/DESCRIPTION

Same package structure, but include a non-empty biocViews field, for example:

biocViews: Software

or another simple non-empty value.

The point is not whether the package is a valid Bioconductor package. The point is that renv uses non-empty biocViews as the trigger.

Required scenarios

Replace the current 8-scenario matrix with a smaller, sharper matrix.

Scenario 1: dependency discovery without biocViews

Purpose: Show baseline behaviour.

Steps:

    run renv::dependencies() or the relevant dependency discovery against fixtures/cranlike-no-biocviews/DESCRIPTION;
    capture discovered dependencies;
    assert that neither BiocManager nor BiocVersion appears.

Expected:

    no BiocManager
    no BiocVersion
    no Bioconductor dependency type

Scenario 2: dependency discovery with non-empty biocViews

Purpose: Prove the crux directly.

Steps:

    run renv::dependencies() or dependency discovery against fixtures/cranlike-with-biocviews/DESCRIPTION;
    capture discovered dependencies;
    assert that both BiocManager and BiocVersion appear;
    capture the dependency Type column and show that they appear under Bioconductor.

Expected:

    BiocManager present
    BiocVersion present
    dependency type includes Bioconductor

This is the most important scenario.

Scenario 3: real-world trigger package metadata (recipes)

Purpose: Connect the minimal fixture to the real package that triggered the support case.

Steps:

    install recipes from PPM / CRAN;
    capture packageDescription("recipes");
    specifically print:
        Package
        Version
        Repository
        biocViews
    show that recipes is CRAN / PPM-installed but has non-empty biocViews.

Expected:

    Repository should indicate CRAN or PPM/Repository source;
    biocViews should be non-empty;
    no claim should be made that recipes is a Bioconductor package.

Scenario 4: snapshot with biocViews fixture in CRAN/PPM-only, Bioc-blocked environment

Purpose: Show the actual blocker.

Steps:

    create a minimal renv project;
    include the cranlike-with-biocviews fixture as a project dependency;
    configure only PPM CRAN repo;
    block Bioconductor hostnames;
    ensure BiocVersion is not installed and not available from configured repos;
    run renv::snapshot();
    capture stdout/stderr and exit status.

Expected:

    snapshot fails or warns in a way attributable to BiocVersion / Bioconductor version resolution;
    the report must clearly state whether the failure is:
        dependency resolution cannot find BiocVersion;
        Bioconductor version validation fails;
        BiocManager attempts to reach Bioconductor;
        or another related error.

Do not overgeneralise. Classify the exact observed failure.

Scenario 5: snapshot without biocViews fixture under same network restrictions

Purpose: Show that the blocked network itself is not the issue.

Steps:

    same as Scenario 4, but use cranlike-no-biocviews;
    PPM reachable;
    Bioconductor blocked;
    run renv::snapshot().

Expected:

    snapshot succeeds;
    no implicit BiocVersion.

This is the key control.

Scenario 6: workaround — project-level renv::settings$bioconductor.version(...)

Purpose: Test whether pinning the Bioconductor version avoids the failure.

Steps:

    same as Scenario 4;
    set renv::settings$bioconductor.version("3.20") before snapshot;
    run snapshot;
    capture status and lockfile.

Expected:

    record whether this succeeds, warns, or fails;
    if it produces an incomplete lockfile, say exactly what is missing.

Scenario 7: workaround — make BiocVersion available

Purpose: Test the hypothesis that the hard blocker is the inferred BiocVersion dependency being unavailable.

Choose the simplest feasible approach. Options:

    install BiocVersion in an open-network preparation step and then run snapshot in blocked mode;
    add a local package cellar containing BiocVersion;
    configure a reachable PPM repository that includes Bioconductor if available;
    or document if this scenario is skipped because no BiocVersion source is available.

Expected:

    if BiocVersion is available, snapshot should get further or succeed;
    if it still fails, capture the next failure in the chain.

Do not fake this result.

Scenario 8: workaround — non-empty renv.bioconductor.repos stub

Purpose: Test the support suggestion, but only as secondary.

Steps:

    same as Scenario 4;
    set options(renv.bioconductor.repos = c(BioCsoft = "<reachable PPM stub URL>"));
    run snapshot.

Expected:

    classify whether this avoids the BiocVersion issue or not.

Scenarios to delete unless still useful

Remove the old scenario that patches renv.lock to see what reintroduces Bioc refs.

That was useful earlier, but it distracts from the actual blocker.

Do not spend much report space on startup / restore unless they reveal something directly related to the implicit BiocVersion dependency.

Required artifacts

For every scenario, save:

artifacts/<scenario>/

  stdout.log

  stderr.log

  result.json

  discovered-dependencies.csv

  session-info.txt

  repos.txt

  renv-settings.json    # if present

  renv.lock             # if produced

``

The result.json must include:

{

  "scenario": "...",

  "ppm_reachable": true,

  "bioconductor_reachable": false,

  "biocviews_present": true,

  "biocmanager_discovered": true,

  "biocversion_discovered": true,

  "snapshot_status": "success|warning|failure|not_run",

  "snapshot_error_classification": "...",

  "renv_lock_written": true,

  "notes": "..."

}

Required report changes

Rewrite artifacts/report.md around this structure:

1. Executive summary

State the actual blocker:

A non-empty biocViews field causes renv dependency discovery to add BiocManager and BiocVersion as implicit dependencies. In a CRAN/PPM-only environment with Bioconductor blocked, BiocVersion cannot be resolved, so renv::snapshot() cannot complete for otherwise CRAN-only projects.

2. Code-path evidence

Include the exact snippet from renv_dependencies_discover_description():

if (nzchar(dcf[["biocViews"]] %||% "")) {

  data[[length(data) + 1L]] <- renv_dependencies_list(

    source = path,

    packages = c(renv_bioconductor_manager(), "BiocVersion")

  )

  names(data)[[length(data)]] <- "Bioconductor"

}

Then explain:

    this is triggered by any non-empty biocViews;
    on R 4.4 this means BiocManager + BiocVersion;
    BiocManager is CRAN, but BiocVersion is Bioconductor;
    therefore CRAN-only PPM cannot satisfy the inferred dependency unless Bioconductor content is mirrored.

3. Minimal fixture proof

Compare dependency discovery for the two local fixtures.

Show a tiny table:

    no biocViews → no BiocVersion;
    non-empty biocViews → BiocManager + BiocVersion.

4. Real package proof

Show recipes metadata:

packageDescription("recipes")[c("Package", "Version", "Repository", "biocViews")]

Make the point:

    recipes is installed from CRAN / PPM;
    recipes has non-empty biocViews;
    this metadata is enough to trigger Bioconductor handling.

5. Snapshot proof under blocked Bioconductor

Compare:

    no biocViews fixture: snapshot succeeds with PPM reachable and Bioconductor blocked;
    with biocViews fixture: snapshot fails / warns due to BiocVersion or Bioconductor version resolution.

6. Workaround analysis

Briefly summarise:

    renv::settings$bioconductor.version("3.20")
    making BiocVersion available
    stub renv.bioconductor.repos

Only discuss what the harness actually proves.

7. Conclusion

Use this language:

This issue is not primarily that Bioconductor repositories appear in the lockfile. The blocker is earlier: dependency discovery converts biocViews metadata into an implicit dependency on BiocVersion. Since BiocVersion is not available from CRAN-only PPM and Bioconductor is blocked, snapshot cannot complete for a project that otherwise uses only CRAN packages.

README changes

Update the README title and first paragraph.

Suggested title:

# renv biocViews → BiocVersion dependency repro

Suggested opening:

This repo demonstrates that renv treats a non-empty biocViews field in a DESCRIPTION file as a Bioconductor signal and injects BiocManager + BiocVersion as implicit dependencies. This can make renv::snapshot() fail in CRAN/PPM-only enterprise environments where Bioconductor is unreachable, even when the user

Remove wording that says the main issue is lockfile contamination.

Implementation notes

    Keep the repo runnable with one command: ./run_matrix.sh.
    Keep output concise and support-ready.
    If a scenario cannot be implemented, mark it as skipped with a clear reason.
    Ensure the final report is something we can send to Posit Support without additional explanation.

Final response expected

When done, return:

    list of files changed;
    brief explanation of changed scenario matrix;
    the new README.md;
    the new generated artifacts/report.md;
    any scenarios that failed unexpectedly;
    exact command used to run the harness.