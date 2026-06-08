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

## Does naming a repo `"CRAN"` cause false *negatives* for real Bioconductor packages?

A natural worry about the new logic: it short-circuits on `identical(repository,
"CRAN")` (step 2) and on `repository %in% names(getOption("repos"))` (step 4), both
returning "not Bioconductor". Posit's [Bioconductor admin
guidance](https://docs.posit.co/rspm/admin/workbench.html) even has admins point a
repo *named* `CRAN` at a "CRAN snapshot compatible with Bioconductor":

```r
# Configure BiocManager to use Posit Package Manager
options(BioC_mirror = "https://[server]/[bioconductor-repo-name]/latest")
options(BIOCONDUCTOR_CONFIG_FILE = "https://[server]/[bioconductor-repo-name]/latest/config.yaml")
Sys.setenv("R_BIOC_VERSION" = "[bioconductor-version]")
# Configure a CRAN snapshot compatible with Bioconductor [bioconductor-version]
options(repos = c(CRAN = "https://[server]/[cran-repo-name]/[snapshot]"))
```

Could a genuine Bioconductor package get caught by the `CRAN` branch and be
mislabelled as non-Bioconductor? **No.** The protection is the same
metadata-vs-name separation that the fix gets *wrong* in the other direction:

- The Bioconductor repo is configured via `BioC_mirror` / `BIOCONDUCTOR_CONFIG_FILE`
  — a **third namespace** that `renv_description_bioconductor()` never consults. It
  is not in `options(repos)`, so it cannot affect classification.
- The repo Posit labels `CRAN` is a *CRAN* snapshot — it serves CRAN packages
  (stamped `RSPM` via PPM, or `CRAN` upstream). Bioconductor packages live in the
  separate Bioc repo. The two never mix, so the `CRAN`-named repo never serves a
  package whose origin is Bioconductor.
- A genuine Bioconductor package never carries `Repository: CRAN`. Verified against
  a live Bioconductor package (limma, from bioconductor.org):

  ```
  Repository: Bioconductor 3.23
  git_url: https://git.bioconductor.org/packages/limma
  biocViews: ExonArray, GeneExpression, ...
  ```

  This hits **step 1** (`grepl("Bioconductor", repository)` → `TRUE`) and returns
  *before* the `CRAN` checks are reached. The `git.bioconductor.org` `git_url` is a
  second backstop at **step 5**. The `identical(repository, "CRAN")` branch only
  fires for packages literally stamped `"CRAN"` (genuine CRAN packages) — a package
  cannot be stamped both `Bioconductor X.Y` and `CRAN`.

So naming a repo `"CRAN"` introduces **no false negative** for real Bioconductor
packages. The classification table:

| Package | `Repository` stamp | New renv verdict | Correct? |
|---|---|---|---|
| Real Bioc pkg (limma), from bioconductor.org | `Bioconductor 3.23` | Bioconductor (step 1) | ✓ |
| Real Bioc pkg via PPM Bioc repo | `RSPM` + `git.bioconductor.org` url | Bioconductor (step 5/6) | ✓ |
| CRAN pkg w/ biocViews (metaRNASeq), upstream CRAN | `CRAN` | not Bioconductor (step 2) | ✓ |
| **CRAN pkg w/ biocViews via PPM** (metaRNASeq) | **`RSPM`** | **Bioconductor (step 6 fallback)** | **✗ — the bug** |

The only misfire remains the false *positive* on the bottom row — the original
defect. The `CRAN`-named-snapshot in Posit's Bioconductor config does not add a new
failure mode; genuine Bioconductor detection is insulated by the same field-vs-name
separation the fix mishandles for PPM-served CRAN packages.

(Note on the fully-configured Bioconductor case: `renv_bioconductor_version()` does
not read `R_BIOC_VERSION` / `BIOCONDUCTOR_CONFIG_FILE` directly — it delegates to
BiocManager, installing it if absent. If an admin set those (per the block above),
BiocManager can resolve the version from PPM without reaching `bioconductor.org`,
which *masks* the misdetection at snapshot time but still writes `Source:
Bioconductor` into `renv.lock` for a CRAN package — a wrong record that can break a
later `restore()`. This delegation step is reasoned from the source, not exercised
by the harness, which sets only `options(repos)` and no Bioconductor variables.)
