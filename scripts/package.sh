#!/usr/bin/env bash
# Monta o pacote da release: <saída>/stemma-<tag>.zip + .sha256 (ADR 0007).
# Precisa do frontend/dist já construído (npm run build). Usado pelo release.yml e pelo CI.
#
#   bash scripts/package.sh v1.4.0 build
set -euo pipefail

tag="${1:?uso: package.sh <tag vX.Y.Z> <pasta de saída>}"
out="${2:?uso: package.sh <tag vX.Y.Z> <pasta de saída>}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
name="stemma-${tag}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/$name"

[ -d "$repo/frontend/dist" ] || { echo "falta frontend/dist (rode npm run build)" >&2; exit 1; }
mkdir -p "$stage/frontend" "$out"
out="$(cd "$out" && pwd)"

py="$(command -v python3 || command -v python)"

# Backend: código, migrations, pyproject e uv.lock; sem testes nem caches. (tar e o zipfile do
# Python em vez de rsync/zip: roda igual no Linux do CI e no Git Bash do Windows.)
mkdir -p "$stage/backend"
tar -C "$repo/backend" --exclude='__pycache__' --exclude='.venv' --exclude='./tests' \
  --exclude='.pytest_cache' --exclude='.mypy_cache' --exclude='.ruff_cache' -cf - . |
  tar -C "$stage/backend" -xf -
cp -r "$repo/frontend/dist" "$stage/frontend/dist"
cp -r "$repo/deploy" "$stage/deploy"
rm -rf "$stage/deploy/tests"
cp "$repo/.env.example" "$repo/README.md" "$repo/CHANGELOG.md" "$stage/"

rm -f "$out/$name.zip"
(cd "$work" && "$py" -m zipfile -c "$out/$name.zip" "$name")
(cd "$out" && sha256sum "$name.zip" > "$name.zip.sha256" && cat "$name.zip.sha256")
