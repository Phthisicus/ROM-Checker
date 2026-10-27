#!/usr/bin/env bash
set -euo pipefail
name="${1:?container name required}"
url="${2:?health URL required}"
scope="${3:-host}"
if [[ "$scope" != host && "$scope" != container ]]; then
  echo "Health probe scope must be host or container." >&2
  exit 1
fi
probe() {
  if [[ "$scope" == container ]]; then
    docker exec "$name" curl --fail --silent --max-time 2 --output /dev/null "$url"
  else
    curl --fail --silent --max-time 2 --output /dev/null "$url"
  fi
}
deadline=$((SECONDS + 60))
echo "Waiting up to 60 seconds for $name at $url"
while (( SECONDS < deadline )); do
  state="$(docker inspect "$name" --format '{{.State.Status}}')"
  if [[ "$state" != running ]]; then
    echo "Container $name is $state before becoming ready." >&2
    docker logs "$name" >&2
    exit 1
  fi
  if probe; then
    echo "$name is ready."
    exit 0
  fi
  sleep 1
done
echo "Container $name did not become healthy within 60 seconds: $url" >&2
docker logs "$name" >&2
exit 1
