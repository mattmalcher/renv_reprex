#!/usr/bin/env bash
# fetch_renv_source.sh — download the renv source files used by this repro.
#
# The fetched files are committed to renv-source/ so a reviewer can read the
# relevant code without installing renv.  Run this script to refresh them or
# to pin a different version.
#
# Usage:
#   ./fetch_renv_source.sh                          # fetch dev HEAD commit (matches Dockerfile)
#   ./fetch_renv_source.sh 1.2.3                    # fetch a released version tag
#   ./fetch_renv_source.sh b1fd8fa843781b4fdebcd0   # fetch a specific commit SHA

set -euo pipefail

# Default: dev commit pinned in the Dockerfile
RENV_REF="${1:-b1fd8fa843781b4fdebcd0e25a78a5cfb15da822}"

# Version tags use v<version> prefix; bare SHAs and 'main' are used as-is
if [[ "$RENV_REF" =~ ^[0-9]+\.[0-9]+ ]]; then
  GIT_REF="v${RENV_REF}"
else
  GIT_REF="$RENV_REF"
fi

BASE_URL="https://raw.githubusercontent.com/rstudio/renv/${GIT_REF}/R"
DEST="$(cd "$(dirname "$0")" && pwd)/renv-source/R"

FILES=(
  dependencies.R    # renv_dependencies_discover_description() — biocViews injection (Path A)
  snapshot.R        # renv_snapshot_description_source() + validate_bioconductor() (Path B)
  bioconductor.R    # renv_bioconductor_version() — the network call path
)

mkdir -p "$DEST"
echo "Fetching renv ${GIT_REF} source files from GitHub..."
echo "  Source: https://github.com/rstudio/renv/tree/${GIT_REF}/R"
echo "  Dest:   ${DEST}/"
echo ""

for f in "${FILES[@]}"; do
  url="${BASE_URL}/${f}"
  dest="${DEST}/${f}"
  echo "  GET ${url}"
  curl -fsSL "$url" -o "$dest"
  echo "       → ${dest} ($(wc -l < "$dest") lines)"
done

echo ""
echo "Done. Ref: ${GIT_REF}"
echo "See renv-source/README.md for annotated line references."
