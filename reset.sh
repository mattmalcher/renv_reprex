#!/usr/bin/env bash
# reset.sh — remove all generated artifacts so the next run starts clean.
#
# Does NOT touch:
#   - renv-source/   (fetched separately via fetch_renv_source.sh)
#   - the Docker image (use --rmi to remove it too)
#
# Usage:
#   ./reset.sh          # clear artifacts only
#   ./reset.sh --rmi    # also remove the Docker image

set -euo pipefail

IMAGE="renv-biocviews-debug"
ARTIFACTS="$(cd "$(dirname "$0")" && pwd)/artifacts"
REMOVE_IMAGE=false

for arg in "$@"; do
  case "$arg" in
    --rmi) REMOVE_IMAGE=true ;;
    *)     echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

echo "Clearing artifacts..."

# Remove per-scenario directories (files may be root-owned from Docker runs)
if docker info &>/dev/null 2>&1; then
  DOCKER="docker"
elif sudo docker info &>/dev/null 2>&1; then
  DOCKER="sudo docker"
else
  DOCKER=""
fi

for dir in "${ARTIFACTS}"/[0-9]*/; do
  [ -d "$dir" ] || continue
  if [ -n "$DOCKER" ]; then
    $DOCKER run --rm -v "${dir}:/toclean" --entrypoint sh "$IMAGE" \
      -c "find /toclean -mindepth 1 -delete" 2>/dev/null || true
  fi
  rm -rf "$dir"
done

rm -f "${ARTIFACTS}/summary.json"

echo "  Cleared: ${ARTIFACTS}/"

if $REMOVE_IMAGE; then
  if [ -n "$DOCKER" ] && $DOCKER image inspect "$IMAGE" &>/dev/null 2>&1; then
    $DOCKER rmi "$IMAGE"
    echo "  Removed Docker image: ${IMAGE}"
  else
    echo "  Image ${IMAGE} not found — skipping."
  fi
fi

echo "Done. Run ./run_matrix.sh to regenerate."
