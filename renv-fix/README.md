# Candidate renv patches for the `biocViews` failure modes

This folder is a **self-contained handoff** for a separate session: candidate
upstream fixes for renv, as unified diffs against **renv 1.2.3**, plus a script
that clones renv, applies them, and runs renv's own test suite so you can spot
regressions before proposing anything to [rstudio/renv](https://github.com/rstudio/renv).

The patches are diffed against the verbatim sources in `../renv-source/R/`
(fetched by `../fetch_renv_source.sh`, so line numbers match `v1.2.3`). They are
**reference drafts to validate, not finished PRs** — variant choice and the
contested `BiocVersion` question are noted below and should go to the maintainers.

## The three failure modes → two code sites

The repro's three failure modes collapse onto **two** lines of logic, both of
which use a non-empty `biocViews` field as the *sole* "this is Bioconductor"
signal. Failure mode C is the downstream tail of A (it is the injected
`BiocVersion` that can never install), so it shares A's code site.

| Failure mode (see ../README.md) | Scenarios | Code site | Patch |
|---|---|---|---|
| **A** — `install()`/`restore()` fails | 1, 2, 8 | `R/dependencies.R` ~602 (dependency injection) | `0002a` **or** `0002b` |
| **B** — `snapshot()` fails | 4, 6, 7 | `R/snapshot.R` ~940 (source inference) | `0001` |
| **C** — `status()`/`activate()` permanently out of sync | 9, 10, 11 | downstream of `R/dependencies.R` ~602 | `0002b` |

## The patches

### `0001-snapshot-source-reorder.patch` — Path B (recommended, safe)

In `renv_snapshot_description_source()` the `biocViews → Source = "Bioconductor"`
check runs **before** the declared-`Repository` check, and overrides it. But by
the time control reaches that line, `renv_record_cranlike(dcf)` has already
confirmed the package is CRAN-like (it has a `Repository:` field). This patch
simply **reorders** the two blocks: a package with `Repository: RSPM/CRAN` is
recorded as `Source = "Repository"`; genuine Bioconductor installs (which carry
**no** CRAN-like `Repository` field) still fall through to the `biocViews` branch
and are classified correctly.

- **Fixes:** scenarios 4, 6, 7 (snapshot no longer probes `bioconductor.org`).
- **Risk:** low — pure block move, no new behavior for genuine bioc packages.
- **One edge case to validate:** a *genuine* Bioconductor package installed via a
  PPM Bioconductor mirror may carry `Repository: RSPM`; after this change it
  records as `Repository` rather than `Bioconductor`. Worth a dedicated test
  fixture either way.

### Path A / C — pick **one** of these two (mutually exclusive; both touch the same block)

`0002a` and `0002b` are **alternatives** — do not apply both. The script applies
one based on `--deps`.

#### `0002a-dependencies-gate-biocversion-on-repository.patch` (conservative)

Only inject the Bioconductor-only `BiocVersion` when the DESCRIPTION does **not**
declare a CRAN-like repository. Mirrors the `0001` predicate.

- **Fixes:** the *installed CRAN-dependency carries `biocViews`* variant.
- **Does NOT fix scenario 8** — a source project that *is* a package has no
  `Repository:` field, so injection still fires. (In practice dependency
  discovery rarely scans installed deps' DESCRIPTIONs, so this patch is close to
  a no-op for normal projects — included for completeness/comparison.)

#### `0002b-dependencies-inject-manager-only.patch` (fixes A **and** C, more contested)

Inject only `BiocManager` (which **is** on CRAN), never the un-obtainable
`BiocVersion`. `BiocManager` can still resolve the Bioconductor release for
genuine bioc projects.

- **Fixes:** scenario 8 (Path A) and scenarios 9–11 (Path C) — no phantom
  un-installable dependency remains, so install/restore succeed and
  status/activate reconcile.
- **Risk / open question for maintainers:** this drops `BiocVersion` as an
  explicit lockfile pin of the Bioconductor release. Issue
  [#2128](https://github.com/rstudio/renv/issues/2128) may specifically want
  `BiocVersion` recorded. **Expect renv tests asserting `BiocVersion` injection
  to move** — that is exactly what the test run will surface, and the signal you
  want before deciding.

## Apply and test

```bash
cd renv-fix
./apply_and_test.sh                 # 0001 + 0002b (default), then run renv tests
./apply_and_test.sh --deps a        # 0001 + 0002a
./apply_and_test.sh --deps none     # 0001 only (the safe Path B fix)
./apply_and_test.sh --ref v1.2.3    # pin a different renv tag/branch/sha
./apply_and_test.sh --no-test       # apply only; patched tree left in .renv-checkout/
```

The script clones `rstudio/renv` at `--ref` (default `v1.2.3`), `git apply`s the
selected patches (with a `--check` first), prints the diffstat, and runs
`testthat::test_local(".")`. Requires `git`, `R` with renv's test deps, and
internet to github.com + CRAN.

### Apply by hand instead

```bash
git clone --branch v1.2.3 https://github.com/rstudio/renv.git
cd renv
git apply /path/to/renv-fix/patches/0001-snapshot-source-reorder.patch
git apply /path/to/renv-fix/patches/0002b-dependencies-inject-manager-only.patch
# or: patch -p1 < .../0001-snapshot-source-reorder.patch
Rscript -e 'testthat::test_local(".")'
```

Targeted test files to read closely after the run:
`tests/testthat/test-bioconductor.R`, `test-snapshot.R`, `test-dependencies.R`.

## Validating against this repro

After confirming the renv test suite is green (or understanding any moved
tests), point the repro's harness at the patched renv to confirm the scenarios
flip from failure to success:

- `0001` should flip **scenarios 4, 6, 7** to success (snapshot completes,
  `metaRNASeq` recorded with `Source = "Repository"`).
- `0002b` should flip **scenario 8** (install succeeds) and **9–11** (status in
  sync).
- `0002a` is expected to leave scenario 8 failing (see above).

See `../README.md` §"How success is measured" for the harness's outcome
definitions. The repro pins renv via `remotes::install_version`; to test the
patched build, install renv from your patched checkout
(`R CMD INSTALL .renv-checkout`) inside the scenario image instead.

## What to send upstream

- **Lead with `0001`** — it is the clean, low-risk fix that closes the
  non-empty-`biocViews` gap left open by
  [#2149](https://github.com/rstudio/renv/issues/2149). Scenarios 4/5 are its
  regression test.
- **Raise Path A (`0002b`) as a discussion**, not an obviously-correct patch:
  "should a project that merely carries `biocViews` get a hard, possibly
  un-obtainable `BiocVersion` dependency?" Reference
  [#2128](https://github.com/rstudio/renv/issues/2128) and
  [#2149](https://github.com/rstudio/renv/issues/2149).
