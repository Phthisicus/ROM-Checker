#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/registry-retry.sh"

: "${IMAGE:?}" "${SOURCE_REF:?}" "${TARGET_TAG:?}" "${EXPECTED_DIGEST:?}"
[[ "$EXPECTED_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]
before="$(registry_retry docker buildx imagetools inspect "$SOURCE_REF" --format '{{json .Manifest}}' | jq -r .digest)"
[[ "$before" == "$EXPECTED_DIGEST" ]] || { echo "Source image digest changed before promotion." >&2; exit 1; }
if registry_retry docker buildx imagetools inspect "$IMAGE:$TARGET_TAG" >/dev/null 2>&1; then
  existing="$(registry_retry docker buildx imagetools inspect "$IMAGE:$TARGET_TAG" --format '{{json .Manifest}}' | jq -r .digest)"
  [[ "$existing" == "$EXPECTED_DIGEST" ]] || {
    echo "Immutable image tag $TARGET_TAG already points to a different digest." >&2
    exit 1
  }
  echo "Reusing verified immutable image tag $TARGET_TAG at $existing"
  exit 0
fi
registry_retry docker buildx imagetools create --tag "$IMAGE:$TARGET_TAG" "$IMAGE@$EXPECTED_DIGEST"
after="$(registry_retry docker buildx imagetools inspect "$IMAGE:$TARGET_TAG" --format '{{json .Manifest}}' | jq -r .digest)"
[[ "$after" == "$EXPECTED_DIGEST" ]] || { echo "Image digest changed during promotion." >&2; exit 1; }
echo "Promoted $IMAGE:$TARGET_TAG at $after"
