#!/usr/bin/env bash
# scripts/pin-image-digests.sh - lock every base image to its exact digest.
#
# A tag like "python:3.13-slim-trixie" can be re-published with new content.
# A digest (sha256:...) always points to the same bytes, so pinning to it makes
# builds fully repeatable. The tag is kept in front for readability:
#   FROM python:3.13-slim-trixie@sha256:abc123...
#
# Usage:
#   ./scripts/pin-image-digests.sh           pin images that are not pinned yet
#   ./scripts/pin-image-digests.sh --update  re-resolve every image (pick up security fixes)
#
# Changes these files in place: */Dockerfile and docker-compose.yml

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

files=(*/Dockerfile docker-compose.yml)

# print every image reference used in FROM lines and compose "image:" lines
list_images() {
    {
        # FROM [--platform=...] image [AS name]
        awk 'toupper($1) == "FROM" {
                 for (i = 2; i <= NF; i++) if ($i !~ /^--/) { print $i; break }
             }' */Dockerfile
        awk '$1 == "image:" { print $2 }' docker-compose.yml
    } | sort -u
}

pinned=0
skipped=0

for ref in $(list_images); do
    tag_ref="${ref%@*}"        # image without any existing @sha256:...

    # skip stage names like "base" or "build" (FROM base AS dev)
    if [[ "$tag_ref" != *:* && "$tag_ref" != */* ]]; then
        continue
    fi

    if [[ "$ref" == *@sha256:* && $UPDATE -eq 0 ]]; then
        echo "already pinned: $ref"
        skipped=$((skipped + 1))
        continue
    fi

    echo "resolving $tag_ref ..."
    docker pull --quiet "$tag_ref" >/dev/null
    digest=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$tag_ref" \
             | head -n 1 | sed 's/.*@//')

    if [[ "$digest" != sha256:* ]]; then
        echo "ERROR: could not find a digest for $tag_ref" >&2
        exit 1
    fi

    new_ref="$tag_ref@$digest"
    # replace the old reference (with or without a digest) in every file
    for f in "${files[@]}"; do
        sed -i "s#${ref//./\\.}\([[:space:]]\|\$\)#${new_ref}\1#g" "$f"
    done
    echo "  -> $new_ref"
    pinned=$((pinned + 1))
done

echo
echo "pinned: $pinned, already pinned: $skipped"
echo "review the changes with: git diff"
