#!/usr/bin/env bash

registry_retry() {
  local attempt status error
  error="$(mktemp)"
  for attempt in 1 2 3; do
    if "$@" 2>"$error"; then
      cat "$error" >&2
      rm -f "$error"
      return 0
    else
      status=$?
    fi
    cat "$error" >&2
    if [ "$attempt" -eq 3 ] || ! grep -Eqi 'timeout|timed out|connection (reset|refused)|temporary|unexpected EOF|too many requests|(^|[^0-9])(429|500|502|503|504)([^0-9]|$)' "$error"; then
      rm -f "$error"
      return "$status"
    fi
    echo "Transient registry error; retrying read ($attempt/3)." >&2
    sleep "$((attempt * 2))"
  done
}
