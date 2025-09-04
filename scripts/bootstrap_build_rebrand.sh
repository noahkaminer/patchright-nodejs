#!/usr/bin/env bash
set -euo pipefail

# --- Config (override via env if you like) ---
: "${GCP_PROJECT:=sheer-health-scratch}"
: "${GAR_REPO:=npm-repo}"
: "${GAR_LOCATION:=us-central1}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-}"      # e.g. v1.52.0 (MUST be a real upstream tag)
PATCHRIGHT_SEMVER="${PATCHRIGHT_SEMVER:-}"        # e.g. 1.52.5 (what you publish as)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAYWRIGHT_DIR="${ROOT_DIR}/playwright"
PATCH_SCRIPT="${ROOT_DIR}/patchright_nodejs_patch.js"
REBRAND_SCRIPT="${ROOT_DIR}/patchright_nodejs_rebranding.js"
REGISTRY_URL="https://${GAR_LOCATION}-npm.pkg.dev/${GCP_PROJECT}/${GAR_REPO}/"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found"; exit 1; }; }
need_cmd git
need_cmd node
need_cmd npm
need_cmd jq

echo "==> GCP: ${GCP_PROJECT} | Repo: ${GAR_REPO} | Location: ${GAR_LOCATION}"
echo "==> Registry: ${REGISTRY_URL}"

# --- Determine Playwright version (from env or helper) ---
if [[ -z "${PLAYWRIGHT_VERSION}" ]]; then
  if [[ -x "${ROOT_DIR}/utils/release_version_check.sh" ]]; then
    OUT="$("${ROOT_DIR}/utils/release_version_check.sh" || true)"
    if grep -qE 'playwright_version=' <<< "${OUT}"; then
      PLAYWRIGHT_VERSION="$(sed -n 's/.*playwright_version=\(v\{0,1\}[0-9][^[:space:]]*\).*/\1/p' <<< "${OUT}" | head -1 | tr -d '[:space:]')"
    fi
  fi
fi
[[ -z "${PLAYWRIGHT_VERSION}" ]] && { echo "Set PLAYWRIGHT_VERSION (e.g., v1.52.0)"; exit 1; }

# Decide what version to publish as:
# Prefer PATCHRIGHT_SEMVER if provided; otherwise mirror the PW tag (strip leading v)
SEMVER="${PATCHRIGHT_SEMVER:-${PLAYWRIGHT_VERSION#v}}"
echo "==> Playwright tag: ${PLAYWRIGHT_VERSION}"
echo "==> Patchright semver to publish: ${SEMVER}"

# --- Fresh clone of Playwright ---
rm -rf "${PLAYWRIGHT_DIR}"
echo "==> Cloning microsoft/playwright @ ${PLAYWRIGHT_VERSION}"
git clone --depth 1 --branch "${PLAYWRIGHT_VERSION}" https://github.com/microsoft/playwright "${PLAYWRIGHT_DIR}"

echo "==> Installing Playwright deps"
( cd "${PLAYWRIGHT_DIR}" && npm ci )

# --- Patch / generate / build / rebrand (mirrors upstream) ---
echo "==> Patching"
( cd "${PLAYWRIGHT_DIR}" && node "${PATCH_SCRIPT}" )

echo "==> Generating channels (non-fatal)"
set +e
( cd "${PLAYWRIGHT_DIR}" && node utils/generate_channels.js ); true
set -e

echo "==> Building Playwright"
( cd "${PLAYWRIGHT_DIR}" && npm run build )

echo "==> Rebranding to Patchright"
( cd "${PLAYWRIGHT_DIR}" && node "${REBRAND_SCRIPT}" )

# --- Override generated package metadata ---
PATCHRIGHT_PKG_DIR="${PLAYWRIGHT_DIR}/packages/patchright"
PATCHRIGHT_PKG_JSON="${PATCHRIGHT_PKG_DIR}/package.json"
[[ -f "${PATCHRIGHT_PKG_JSON}" ]] || { echo "Missing ${PATCHRIGHT_PKG_JSON}"; exit 1; }

echo "==> Applying name @sheer/patchright, registry, and version"
tmp="$(mktemp)"
jq \
  --arg name "@sheer/patchright" \
  --arg reg  "${REGISTRY_URL}" \
  --arg ver  "${SEMVER}" \
  '.name=$name | .publishConfig.registry=$reg | .version=$ver' \
  "${PATCHRIGHT_PKG_JSON}" > "${tmp}"
mv "${tmp}" "${PATCHRIGHT_PKG_JSON}"

echo "==> package.json summary:"
jq -r '.name, .version, .publishConfig.registry' "${PATCHRIGHT_PKG_JSON}" | nl -ba

# --- Copy your external (consumer-facing) README into the publish dir ---
# Keep your internal instructions in README-SHEER.md at repo root (not copied).
if [[ -f "${ROOT_DIR}/README.md" ]]; then
  rm -f "${PATCHRIGHT_PKG_DIR}/README.md"
  cp "${ROOT_DIR}/README.md" "${PATCHRIGHT_PKG_DIR}/README.md"
  echo "==> Copied README.md into publish dir"
else
  echo "WARN: No README.md found at repo root; package will use upstream README if present."
fi

echo "==> Ready to publish from: ${PATCHRIGHT_PKG_DIR}"
echo "    Next: pnpm run release:auth  &&  pnpm run release:publish"
