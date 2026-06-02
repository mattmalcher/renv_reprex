#!/usr/bin/env bash
#
# apply_and_test.sh — clone renv at the pinned version, apply the candidate
# patches from ./patches, and run renv's own test suite to spot regressions.
#
# Usage:
#   ./apply_and_test.sh                 # snapshot fix + dependencies variant b (default)
#   ./apply_and_test.sh --deps a        # snapshot fix + dependencies variant a
#   ./apply_and_test.sh --deps none     # snapshot fix only
#   ./apply_and_test.sh --ref v1.2.3    # pin a different renv tag/branch/sha
#   ./apply_and_test.sh --no-test       # apply only, skip the test run
#
# Requires: git, R (with the 'renv' build/test deps available), internet access
# to github.com and CRAN. Run from inside the renv-fix/ folder.

set -euo pipefail

REF="v1.2.3"
DEPS_VARIANT="b"
RUN_TESTS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)      REF="$2"; shift 2 ;;
    --deps)     DEPS_VARIANT="$2"; shift 2 ;;
    --no-test)  RUN_TESTS=0; shift ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES="$HERE/patches"
WORK="$HERE/.renv-checkout"

echo ">> renv ref:            $REF"
echo ">> dependencies variant: $DEPS_VARIANT"

# 1. fresh checkout of renv at the pinned ref
rm -rf "$WORK"
git clone --quiet --depth 1 --branch "$REF" https://github.com/rstudio/renv.git "$WORK"
cd "$WORK"

# 2. select patches to apply
TO_APPLY=( "$PATCHES/0001-snapshot-source-reorder.patch" )
case "$DEPS_VARIANT" in
  a)    TO_APPLY+=( "$PATCHES/0002a-dependencies-gate-biocversion-on-repository.patch" ) ;;
  b)    TO_APPLY+=( "$PATCHES/0002b-dependencies-inject-manager-only.patch" ) ;;
  none) ;;
  *) echo "invalid --deps value: $DEPS_VARIANT (expected a|b|none)" >&2; exit 2 ;;
esac

# 3. verify then apply
echo ">> checking patches apply..."
git apply --check "${TO_APPLY[@]}"
git apply "${TO_APPLY[@]}"
echo ">> applied:"
printf '   %s\n' "${TO_APPLY[@]##*/}"
echo ">> diff against $REF:"
git --no-pager diff --stat

# 4. run renv's test suite
if [[ "$RUN_TESTS" -eq 1 ]]; then
  echo ">> running renv test suite (testthat)..."
  # renv uses testthat; test_local() runs tests/testthat against the source tree.
  Rscript -e 'if (!requireNamespace("testthat", quietly=TRUE)) install.packages("testthat", repos="https://cloud.r-project.org"); testthat::test_local(".")'
  echo
  echo ">> Suggested targeted files to eyeball (bioc/snapshot/deps related):"
  echo "   tests/testthat/test-bioconductor.R"
  echo "   tests/testthat/test-snapshot.R"
  echo "   tests/testthat/test-dependencies.R"
else
  echo ">> --no-test: skipping test run. Patched tree is at: $WORK"
fi
