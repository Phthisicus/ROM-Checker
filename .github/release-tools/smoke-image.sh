#!/usr/bin/env bash
set -euo pipefail
image="${1:?image required}"
version="${2:?version required}"
revision="${3:?revision required}"
name="romchecker-release-${GITHUB_RUN_ID:-local}-${RANDOM}"
cleanup() {
  docker logs "$name" || true
  docker rm -f -v "$name" >/dev/null || true
}
trap cleanup EXIT
test "$(docker inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')" = "$version"
test "$(docker inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')" = "$revision"
docker run --rm --entrypoint cat "$image" /app/LICENSE | cmp - LICENSE
identity="$(docker run --rm --entrypoint cat "$image" /app/build-info.json)"
frontend_identity="$(docker run --rm --entrypoint cat "$image" /app/web/client/dist/build-info.json)"
test "$identity" = "$frontend_identity"
release="$(docker run --rm --entrypoint cat "$image" /app/release-info.json)"
echo "$release" | jq -e --argjson build "$identity" '
  .version == $build.version and .channel == $build.channel and .commit == $build.commit
  and .metadataFormatVersion == 1 and (.notes | length > 0)
  and (.upgradeNotes | type == "array") and (.limitations | type == "array")'
test "$(docker run --rm --entrypoint cat "$image" /app/release-notes.md)" = "$(echo "$release" | jq -r .notes)"
echo "$identity" | jq -e --arg version "$version" --arg revision "$revision" '
  .version == $version and .commit == $revision and .schemaVersion == 1
  and (.channel == "development" or .channel == "beta" or .channel == "stable")
  and (.buildNumber > 0) and (.buildAttempt > 0)
  and (.builtUtc | test("^[0-9]{4}-"))
  and (.workflowUrl | test("^https://github.com/Phthisicus/ROM-Checker/actions/runs/[0-9]+$"))'
for field in "build-number buildNumber" "build-attempt buildAttempt" "channel channel" "workflow-url workflowUrl" "schema-version schemaVersion" "metadata-format-version metadataFormatVersion"; do
  read -r label property <<< "$field"
  test "$(docker inspect "$image" --format "{{index .Config.Labels \"io.romchecker.$label\"}}")" = "$(echo "$identity" | jq -r ".$property")"
done
test "$(docker inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.created"}}')" = "$(echo "$identity" | jq -r .builtUtc)"
docker run --rm --entrypoint sh "$image" -c 'grep -F -l -- "$1" /app/web/client/dist/assets/*.js >/dev/null' -- "$version"
docker run -d --name "$name" \
  -e ROMCHECKER_PASSWORD=release-fixture-only-password \
  -e ROMCHECKER_VERSION=runtime-override-must-not-change-identity \
  -e ROMCHECKER_COMMIT=runtime-override-must-not-change-identity \
  -e ROMCHECKER_PATH_BASE=/roms "$image" >/dev/null
bash "$(dirname "$0")/wait-for-http.sh" "$name" http://127.0.0.1:8080/roms/healthz container
test "$(docker exec "$name" id -u)" = 10001
docker exec "$name" curl --fail --silent http://127.0.0.1:8080/roms/ | grep 'content="/roms"'
test "$(docker exec "$name" curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8080/roms/api/jobs)" = 401
docker exec "$name" curl --fail --silent -c /tmp/release-cookies \
  -H 'X-RomChecker: 1' -H 'Content-Type: application/json' \
  --data '{"password":"release-fixture-only-password"}' http://127.0.0.1:8080/roms/api/login >/dev/null
docker exec "$name" curl --fail --silent -b /tmp/release-cookies http://127.0.0.1:8080/roms/api/info \
  | jq -e --argjson build "$identity" '
    .version == $build.version and .commit == $build.commit
    and .buildNumber == $build.buildNumber and .buildAttempt == $build.buildAttempt
    and .channel == $build.channel and .workflowUrl == $build.workflowUrl
    and (.builtUtc | sub("\\+00:00$"; "Z")) == $build.builtUtc
    and .schema.version == $build.schemaVersion'
docker exec "$name" curl --fail --silent -b /tmp/release-cookies http://127.0.0.1:8080/roms/api/diagnostics/build \
  | jq -e --argjson build "$identity" '.build.version == $build.version and .build.buildNumber == $build.buildNumber and .schema.version == $build.schemaVersion'
docker exec "$name" curl --fail --silent -b /tmp/release-cookies http://127.0.0.1:8080/roms/api/system \
  | jq -e --argjson release "$release" '.release == $release and .system.scope == "Container" and (.system.runtime | length > 0)'
docker exec "$name" curl --fail --silent -b /tmp/release-cookies -X POST -H 'X-RomChecker: 1' http://127.0.0.1:8080/roms/api/updates/check \
  | jq -e '.status == "disabled"'
