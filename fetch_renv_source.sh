#!/usr/bin/env bash
# fetch_renv_source.sh — download the renv source files used by this repro.
#
# The fetched files are committed to renv-source/ so a reviewer can read the
# relevant code without installing renv.  Run this script to refresh them or
# to pin a different version.
#
# Usage:
#   ./fetch_renv_source.sh          # fetch renv 1.2.3 (default, matches Dockerfile)
#   ./fetch_renv_source.sh 1.1.4    # fetch a specific version

set -euo pipefail

RENV_VERSION="${1:-1.2.3}"
BASE_URL="https://raw.githubusercontent.com/rstudio/renv/v${RENV_VERSION}/R"
DEST="$(cd "$(dirname "$0")" && pwd)/renv-source/R"

FILES=(
  dependencies.R    # renv_dependencies_discover_description() — the biocViews trigger
  bioconductor.R    # renv_bioconductor_version() — the network call path
)

mkdir -p "$DEST"
echo "Fetching renv ${RENV_VERSION} source files from GitHub..."
echo "  Source: https://github.com/rstudio/renv/tree/v${RENV_VERSION}/R"
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
echo "Done. Version: ${RENV_VERSION}"
echo "See renv-source/README.md for annotated line references."
