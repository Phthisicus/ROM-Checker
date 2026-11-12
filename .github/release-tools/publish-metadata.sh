#!/usr/bin/env bash
set -euo pipefail
tag="${IMAGE:?}:${VERSION:?}-metadata"
name="romchecker-metadata-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
directory="$(mktemp -d)"
cleanup() {
  docker rm "$name" >/dev/null 2>&1 || true
  rm -f "$directory/release-info.json" "$directory/expected.json" "$directory/inspect-error"
  rmdir "$directory"
}
trap cleanup EXIT
docker pull "${IMAGE}:${VERSION}"
docker run --rm --entrypoint cat "${IMAGE}:${VERSION}" /app/release-info.json > "$directory/expected.json"
jq -e --arg version "$VERSION" --arg commit "${SOURCE_SHA:?}" --arg channel "${CHANNEL:?}" \
  '.version == $version and .commit == $commit and .channel == $channel and .metadataFormatVersion == 1' \
  "$directory/expected.json" >/dev/null
if docker buildx imagetools inspect "$tag" >/dev/null 2>"$directory/inspect-error"; then
  echo "Verifying existing immutable release metadata."
elif grep -Eqi 'manifest unknown|not found' "$directory/inspect-error"; then
  # A retry must reuse the notes baked into the immutable application image.
  cp "$directory/expected.json" release-info.json
  docker buildx build --target release-metadata --provenance=false --sbom=false --push --tag "$tag" \
    --build-arg "VERSION=$VERSION" --build-arg "REVISION=${SOURCE_SHA:?}" \
    --build-arg "CHANNEL=${CHANNEL:?}" --build-arg "BUILD_NUMBER=${BUILD_NUMBER:?}" \
    --build-arg "BUILD_ATTEMPT=${BUILD_ATTEMPT:?}" --build-arg "BUILT_UTC=${BUILT_UTC:?}" \
    --build-arg "WORKFLOW_URL=${WORKFLOW_URL:?}" .
else
  cat "$directory/inspect-error" >&2
  exit 1
fi
docker pull "$tag"
docker create --name "$name" "$tag" /unused >/dev/null
docker cp "$name:/release-info.json" "$directory/release-info.json"
cmp "$directory/expected.json" "$directory/release-info.json"
