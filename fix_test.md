# Testing renv dev HEAD against the repro harness

**Branch:** `dev/renv-dev-head`  
**renv commit:** `b1fd8fa843781b4fdebcd0e25a78a5cfb15da822`  
**Commit message:** "don't treat biocViews as proof of bioconductor origin (#2306)"  
**Tested:** 2026-06-08

## Result

All 11 scenarios were re-run against the dev commit. **The fix does not resolve
any of the failing scenarios** (4–11). Outcomes are identical to renv 1.2.3.

## What the fix does

`renv_description_bioconductor()` in `bioconductor.R` was rewritten. Where 1.2.3
treated any package with a `biocViews` field as Bioconductor-origin, the dev
version now interrogates the `Repository` field first:

1. If `Repository` contains `"Bioconductor"` → Bioconductor origin ✓
2. If `Repository` is `"CRAN"` → not Bioconductor ✓
3. If `Repository` matches a known CRAN mirror URL → not Bioconductor ✓
4. If `Repository` is in `names(getOption("repos"))` or matches a URL in the
   active repos → not Bioconductor ✓
5. If no `Repository`, check `git_url` for `"bioconductor"` → Bioconductor ✓
6. Otherwise (`biocViews` present, no contradicting signal) → Bioconductor (historical fallback)

## Why it still fails for PPM users

The test package (metaRNASeq) is installed from Posit Package Manager and has
`Repository: RSPM` in its installed DESCRIPTION. Steps 1–4 all evaluate to
false:

- `"RSPM"` does not contain `"Bioconductor"`
- `"RSPM"` is not `"CRAN"`
- `"RSPM"` is not a CRAN mirror URL
- `"RSPM"` is not in `names(getOption("repos"))` — the session repos option is
  `c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest")`,
  named `"CRAN"`, not `"RSPM"`

So execution reaches step 6, the biocViews fallback fires, and renv attempts
Bioconductor version validation — which fails when bioconductor.org is
unreachable.

## Where `Repository: RSPM` comes from

PPM stamps `Repository: RSPM` into the package tarball **before it is
downloaded**. This was verified by inspecting the raw tarball directly from PPM:

```
curl -sL "https://packagemanager.posit.co/cran/__linux__/noble/latest/src/contrib/metaRNASeq_1.0.8.tar.gz" \
  | tar -xzO metaRNASeq/DESCRIPTION | grep Repository
# Repository: RSPM
```

The same package on CRAN carries `Repository: CRAN`. PPM rewrites this field
when it re-serves the package. R's `install.packages()` is not involved — the
stamp is in the tarball itself.

The `x-repository-type: RSPM` HTTP header PPM returns on every request is a
separate (consistent) signal of the same fact.

## What a complete fix would require

The fix works for users who name their PPM repo `"RSPM"` in `options(repos)`
(step 4 would match). But naming PPM as `"CRAN"` is the standard practice —
it's what makes PPM a transparent drop-in replacement — so the mismatch affects
the typical enterprise PPM user.

A complete fix would need one of:

- **Explicit RSPM recognition:** treat `Repository: RSPM` (and any other known
  PPM stamps) as non-Bioconductor, independent of how the user named their repo.
- **URL matching:** match the `Repository` field value against known PPM
  hostnames (`packagemanager.posit.co`, `packagemanager.rstudio.com`) rather
  than against the user-assigned name.
