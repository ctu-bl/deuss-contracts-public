#!/usr/bin/env bash
set -eo pipefail

medusa_image="${MEDUSA_IMAGE:-deuss-medusa:local}"
medusa_dockerfile="${MEDUSA_DOCKERFILE:-dockerfiles/Dockerfile.medusa}"
medusa_build_context="${MEDUSA_BUILD_CONTEXT:-.}"
config_path="${MEDUSA_CONFIG:-medusa.json}"
foundry_image="${FOUNDRY_IMAGE:-ghcr.io/foundry-rs/foundry:v1.7.0}"
base_medusa_image="${BASE_MEDUSA_IMAGE:-ghcr.io/crytic/medusa:latest}"

cpus="${MEDUSA_CPUS:-2}"
memory="${MEDUSA_MEMORY:-10g}"

platform_args=()

case "$(uname -m)" in
  arm64|aarch64)
    platform_args=(--platform linux/amd64)
    ;;
esac

tty_args=()
if [ -t 0 ] && [ -t 1 ]; then
  tty_args=(-it)
fi

slither_args=("--use-slither=false")
for arg in "$@"; do
  case "${arg}" in
    --use-slither|--use-slither=*|--use-slither-force|--use-slither-force=*)
      slither_args=()
      break
      ;;
  esac
done

docker build \
  --quiet \
  "${platform_args[@]}" \
  --build-arg "FOUNDRY_IMAGE=${foundry_image}" \
  --build-arg "MEDUSA_IMAGE=${base_medusa_image}" \
  -f "${medusa_dockerfile}" \
  -t "${medusa_image}" \
  "${medusa_build_context}" >/dev/null

exec docker run \
  --rm \
  "${tty_args[@]}" \
  "${platform_args[@]}" \
  --cpus "${cpus}" \
  --memory "${memory}" \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "${PWD}:/src" \
  -w /src \
  "${medusa_image}" \
  medusa fuzz \
    --config "${config_path}" \
    "${slither_args[@]}" \
    "$@"
