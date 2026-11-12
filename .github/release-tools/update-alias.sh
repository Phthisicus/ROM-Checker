#!/usr/bin/env bash
set -euo pipefail

case "${BRANCH:?}" in
  development) alias=development ;;
  beta) alias=beta ;;
  main) alias=latest ;;
  *) echo "Unsupported channel branch: $BRANCH" >&2; exit 1 ;;
esac
head="$(gh api "repos/${REPOSITORY:?}/git/ref/heads/$BRANCH" --jq .object.sha)"
if [ "$head" != "${SOURCE_SHA:?}" ]; then
  echo "A newer push exists. Keeping channel aliases unchanged."
  echo "moved=false" >> "${GITHUB_OUTPUT:?}"
  exit 0
fi
if [ "$BRANCH" = development ]; then
  docker buildx imagetools create --tag "${IMAGE:?}:$alias" "${IMAGE}@${DIGEST:?}"
else
  docker buildx imagetools create --tag "${IMAGE:?}:$alias" --tag "$IMAGE:$BRANCH-sha-$SOURCE_SHA" "${IMAGE}@${DIGEST:?}"
fi
echo "moved=true" >> "${GITHUB_OUTPUT:?}"
