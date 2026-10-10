#!/usr/bin/env sh
# Build only unless a deployment action is explicitly requested.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$PROJECT_DIR"
ACTION=${1:-build}
case "$ACTION" in
  build|sync|sync_prod) ;;
  *) printf 'Usage: %s [build|sync|sync_prod]\n' "$0" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  printf 'Only one action may be supplied.\n' >&2
  exit 2
fi

if command -v emacs >/dev/null 2>&1; then
  # Loading in batch normally auto-publishes. Disable that and invoke once.
  DAMAGEBDD_PUBLISH_NO_AUTO=1 emacs -Q --batch \
    -l "$SCRIPT_DIR/publish.el" --eval '(damagebdd-publish)'
elif command -v docker >/dev/null 2>&1; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) PROJECT_DIR=$(pwd -W 2>/dev/null || pwd) ;;
  esac
  docker run --rm -v "$PROJECT_DIR":/project -w /project \
    -e DAMAGEBDD_PUBLISH_NO_AUTO=1 -e DAMAGEBDD_SITE_URL -e SOURCE_DATE_EPOCH \
    "${DAMAGEBDD_EMACS_IMAGE:-silex/emacs:latest}" \
    emacs -Q --batch -l /project/scripts/publish.el --eval '(damagebdd-publish)'
else
  printf 'Error: Emacs or Docker is required to publish this Org site.\n' >&2
  exit 1
fi

# set -e prevents deployment after a failed export. No deployment occurs by default.
case "$ACTION" in
  sync)
    sudo rsync -av --delete "$PROJECT_DIR/public/" "${DAMAGEBDD_LOCAL_TARGET:-/var/www/damagebdd/}"
    ;;
  sync_prod)
    rsync -avz --delete -e ssh "$PROJECT_DIR/public/" "${DAMAGEBDD_DEPLOY_TARGET:-root@node0:/var/www/damagebdd/}"
    ;;
esac
