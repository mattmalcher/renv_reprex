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
# PPM
curl -sL "https://packagemanager.posit.co/cran/__linux__/noble/latest/src/contrib/metaRNASeq_1.0.8.tar.gz" \
  | tar -xzO metaRNASeq/DESCRIPTION | grep Repository
# Repository: RSPM

# CRAN
curl -sL "https://cran.r-project.org/src/contrib/metaRNASeq_1.0.8.tar.gz" \
  | tar -xzO metaRNASeq/DESCRIPTION | grep Repository
# Repository: CRAN
```

The tarballs are otherwise identical in structure; PPM rewrites only the
`Repository` field when it re-serves the package. R's `install.packages()` is not involved — the
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

## Package metadata vs repo name

The argument above turns on two distinct things:

- **Package metadata** — `Repository: RSPM` is a fixed identifier PPM bakes into
  every tarball it serves, representing PPM's identity as the serving infrastructure.
- **Repo name** — the label the user (or administrator) assigns to the PPM URL in
  `options(repos)`, e.g. `c(CRAN = "https://packagemanager.posit.co/...")`.

**The root cause is a namespace mismatch.** renv takes a value from the *package
metadata* namespace (the `Repository` DESCRIPTION field) and matches it against the
*session configuration* namespace (the names and URLs in `options(repos)`):

```r
repository <- dcf[["Repository"]]              # package metadata: "RSPM"
repository %in% names(getOption("repos"))      # session config:   c("CRAN")
any(renv_repos_matches(repository, repos))     # session config:   the repo URLs
```

`renv_repos_matches()` is just `url %in% repos` after trimming slashes — an exact
string compare, with no host parsing. So the field value can only match if it is
*literally identical* to a repo name or a full repo URL. These are different
namespaces that happen to collide for CRAN and nothing else:

- For CRAN they coincide by convention — the field value and the conventional repo
  name are both `"CRAN"`, so the comparison succeeds.
- For PPM they don't — the field is a fixed service identifier (`"RSPM"`),
  independent of what the user named the repo, and it is neither a repo name nor a
  URL, so no branch can ever match.

renv's fix relies on the CRAN coincidence holding universally. It does not: a
metadata stamp is not a repo name.

**Posit's own documentation reinforces the mismatch.** The [Workbench + Package
Manager admin guide](https://docs.posit.co/rspm/admin/workbench.html#internal-packages-and-cran-packages)
explicitly instructs administrators to configure `repos.conf` as:

```
CRAN=https://[package-manager-server-address]/[cran-repo-name]/latest
Internal=https://[package-manager-server-address]/[internal-repo-name]/latest
```

and states: *"the repo containing CRAN packages should be indexed with the keyword
`CRAN`."*

Following this guidance, the session repos will be `c(CRAN = "https://...")`, so
`names(getOption("repos"))` will be `"CRAN"` — and `"RSPM" %in% c("CRAN")` is
always `FALSE`.

**Confirmed: R preserves the tarball value.** The installed `DESCRIPTION` captured
in `artifacts/4` shows `Repository: RSPM` — identical to the value in the raw PPM
tarball (verified above). R's `install.packages()` does not overwrite the
`Repository` field with the user's repo name; it preserves whatever PPM stamped.
So the value renv reads at restore time is the fixed service identifier (`"RSPM"`),
never the user's repo name.

The one case not yet exercised is a session that *names* its PPM repo `"RSPM"` in
`options(repos)` (rather than `"CRAN"`). There step 4 would match and the fix would
work — but that naming is non-standard and contradicts Posit's own admin guidance
above, so it does not describe the typical PPM user.
