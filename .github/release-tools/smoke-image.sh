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
docker run -d --name "$name" \
  -e ROMCHECKER_PASSWORD=release-fixture-only-password \
  -e ROMCHECKER_PATH_BASE=/roms "$image" >/dev/null
bash "$(dirname "$0")/wait-for-http.sh" "$name" http://127.0.0.1:8080/roms/healthz container
test "$(docker exec "$name" id -u)" = 10001
docker exec "$name" curl --fail --silent http://127.0.0.1:8080/roms/ | grep 'content="/roms"'
test "$(docker exec "$name" curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8080/roms/api/jobs)" = 401
docker exec "$name" curl --fail --silent -c /tmp/release-cookies \
  -H 'X-RomChecker: 1' -H 'Content-Type: application/json' \
  --data '{"password":"release-fixture-only-password"}' http://127.0.0.1:8080/roms/api/login >/dev/null
docker exec "$name" curl --fail --silent -b /tmp/release-cookies http://127.0.0.1:8080/roms/api/info \
  | jq -e --arg version "$version" --arg revision "$revision" '.version == $version and .commit == $revision'
