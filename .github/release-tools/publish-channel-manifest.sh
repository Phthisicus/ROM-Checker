#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE:?}" "${CHANNEL:?}" "${VERSION:?}" "${BUILD_VERSION:?}" "${IMAGE_TAG:?}"
: "${IMAGE_DIGEST:?}" "${SOURCE_SHA:?}" "${BUILD_NUMBER:?}" "${SCHEMA_VERSION:?}" "${PUBLISHED_UTC:?}"
: "${RELEASE_NOTES_URL:?}"
source "$(dirname "$0")/registry-retry.sh"

[[ "$IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]
[[ "$SOURCE_SHA" =~ ^[a-f0-9]{40}$ ]]
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]
[[ "$SCHEMA_VERSION" =~ ^[1-9][0-9]*$ ]]

before="$(registry_retry docker buildx imagetools inspect "$IMAGE:$IMAGE_TAG" --format '{{json .Manifest}}' | jq -r .digest)"
[[ "$before" == "$IMAGE_DIGEST" ]] || { echo "The application tag does not resolve to the approved digest." >&2; exit 1; }

immutable_tag="$(node .github/release-tools/semver.mjs docker-tag "$VERSION")-manifest"
if registry_retry docker buildx imagetools inspect "$IMAGE:$immutable_tag" >/dev/null 2>&1; then
  registry_retry docker pull "$IMAGE:$immutable_tag"
  for pair in \
    "io.romchecker.manifest-format-version=1" \
    "io.romchecker.channel=$CHANNEL" \
    "io.romchecker.version=$VERSION" \
    "io.romchecker.build-version=$BUILD_VERSION" \
    "io.romchecker.image=$IMAGE" \
    "io.romchecker.image-digest=$IMAGE_DIGEST" \
    "io.romchecker.commit=$SOURCE_SHA" \
    "io.romchecker.build-number=$BUILD_NUMBER" \
    "io.romchecker.schema-version=$SCHEMA_VERSION"
  do
    key="${pair%%=*}"
    expected="${pair#*=}"
    actual="$(docker inspect "$IMAGE:$immutable_tag" --format "{{index .Config.Labels \"$key\"}}")"
    [[ "$actual" == "$expected" ]] || { echo "Existing immutable manifest conflicts at $key." >&2; exit 1; }
  done
  immutable_digest="$(registry_retry docker buildx imagetools inspect "$IMAGE:$immutable_tag" --format '{{json .Manifest}}' | jq -r .digest)"
  [[ "$immutable_digest" =~ ^sha256:[a-f0-9]{64}$ ]]
  registry_retry docker buildx imagetools create --tag "$IMAGE:$CHANNEL-manifest" "$IMAGE@$immutable_digest"
else
  registry_retry docker buildx build --push \
    --file .github/release-tools/channel-manifest.Dockerfile \
    --tag "$IMAGE:$immutable_tag" \
    --tag "$IMAGE:$CHANNEL-manifest" \
    --build-arg "CHANNEL=$CHANNEL" \
    --build-arg "VERSION=$VERSION" \
    --build-arg "BUILD_VERSION=$BUILD_VERSION" \
    --build-arg "IMAGE=$IMAGE" \
    --build-arg "IMAGE_TAG=$IMAGE_TAG" \
    --build-arg "IMAGE_DIGEST=$IMAGE_DIGEST" \
    --build-arg "COMMIT=$SOURCE_SHA" \
    --build-arg "BUILD_NUMBER=$BUILD_NUMBER" \
    --build-arg "SCHEMA_VERSION=$SCHEMA_VERSION" \
    --build-arg "PUBLISHED_UTC=$PUBLISHED_UTC" \
    --build-arg "RELEASE_NOTES_URL=$RELEASE_NOTES_URL" .
fi

manifest_digest="$(registry_retry docker buildx imagetools inspect "$IMAGE:$CHANNEL-manifest" --format '{{json .Manifest}}' | jq -r .digest)"
[[ "$manifest_digest" =~ ^sha256:[a-f0-9]{64}$ ]]
registry_retry docker pull "$IMAGE:$CHANNEL-manifest"
for pair in \
  "io.romchecker.manifest-format-version=1" \
  "io.romchecker.channel=$CHANNEL" \
  "io.romchecker.version=$VERSION" \
  "io.romchecker.build-version=$BUILD_VERSION" \
  "io.romchecker.image=$IMAGE" \
  "io.romchecker.image-digest=$IMAGE_DIGEST" \
  "io.romchecker.commit=$SOURCE_SHA" \
  "io.romchecker.build-number=$BUILD_NUMBER" \
  "io.romchecker.schema-version=$SCHEMA_VERSION"
do
  key="${pair%%=*}"
  expected="${pair#*=}"
  actual="$(docker inspect "$IMAGE:$CHANNEL-manifest" --format "{{index .Config.Labels \"$key\"}}")"
  [[ "$actual" == "$expected" ]] || { echo "Published channel manifest failed verification: $key" >&2; exit 1; }
done
echo "manifest_digest=$manifest_digest" >> "$GITHUB_OUTPUT"
