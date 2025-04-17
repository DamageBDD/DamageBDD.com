#!/usr/bin/env sh

PROJECT_NAME="damagebdd"
PUBLISH_FILE="scripts/publish.el"

# Normalize PWD for Docker on Windows (Git Bash/WSL compatible)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    PROJECT_DIR=$(pwd -W 2>/dev/null || pwd) # Git Bash & MSYS
    ;;
  *)
    PROJECT_DIR=$(pwd)
    ;;
esac

# Check for emacs
if command -v emacs >/dev/null 2>&1; then
  echo "Emacs found. Running locally..."
  emacs --batch \
        -l "$PUBLISH_FILE" \
        --eval "(org-publish-project \"$PROJECT_NAME\" t)"

# Fallback to Docker
elif command -v docker >/dev/null 2>&1; then
  echo "Emacs not found. Running with Docker..."
  docker run --rm \
    -v "$PROJECT_DIR":/project \
    -w /project \
    silex/emacs:latest \
    emacs --batch \
          -l /project/"$PUBLISH_FILE" \
          --eval "(org-publish-project \"$PROJECT_NAME\" t)"

else
  echo "Error: Neither Emacs nor Docker is available." >&2
  exit 1
fi

