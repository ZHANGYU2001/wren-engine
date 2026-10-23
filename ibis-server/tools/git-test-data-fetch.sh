#!/bin/sh
set -eu

# Cargo fetches these large fixture repositories even for a production build.
# Keep the requested commit and all files, fetching only a shallow history.
test_data_repo=false
for argument in "$@"; do
  case "$argument" in
    https://github.com/apache/datafusion-testing.git|https://github.com/apache/parquet-testing.git|https://github.com/apache/arrow-testing|https://github.com/apache/arrow-testing.git)
      test_data_repo=true
      ;;
  esac
done

if [ "$test_data_repo" = true ]; then
  depth=${TEST_DATA_HISTORY_DEPTH:-1}
  case "$depth" in
    ''|*[!0-9]*) printf '%s\n' 'TEST_DATA_HISTORY_DEPTH must be a nonnegative integer.' >&2; exit 2 ;;
  esac
  if [ "$depth" -gt 0 ]; then
    if [ "${1:-}" = fetch ]; then
      printf 'Fetching pinned Apache test data with history depth %s\n' "$depth" >&2
      shift
      exec /usr/bin/git fetch "--depth=$depth" "$@"
    fi
    # Current Cargo prepends this global Git safety option before `fetch`.
    if [ "${1:-}" = -c ] && [ "${2:-}" = core.fsmonitor=false ] && [ "${3:-}" = fetch ]; then
      printf 'Fetching pinned Apache test data with history depth %s\n' "$depth" >&2
      shift 3
      exec /usr/bin/git -c core.fsmonitor=false fetch "--depth=$depth" "$@"
    fi
  fi
fi

exec /usr/bin/git "$@"
