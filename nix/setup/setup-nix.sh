#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_ENV:?Set GITHUB_ENV to the runner environment file}"
: "${GITHUB_PATH:?Set GITHUB_PATH to the runner PATH file}"
: "${GITHUB_OUTPUT:?Set GITHUB_OUTPUT to the runner output file}"

case ${SETUP_NIX_TRUST_RUNNER:-false} in
true | false) ;;
*)
  echo 'trust-runner must be true or false' >&2
  exit 2
  ;;
esac

case ${SETUP_NIX_USE_G7C_CACHE:-true} in
true)
  cache_config=$'\nextra-substituters = https://cache.g7c.us'
  cache_config+=$'\nextra-trusted-public-keys = cache.g7c.us:dSWpE2B5zK/Fahd7npIQWM4izRnVL+a4LiCAnrjdoFY='
  ;;
false) cache_config= ;;
*)
  echo 'use-g7c-cache must be true or false' >&2
  exit 2
  ;;
esac

work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/setup-nix.XXXXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

os=$(uname -s)
base_config='extra-experimental-features = nix-command flakes'
if [[ $os == Darwin ]]; then
  base_config+=$'\nssl-cert-file = /etc/ssl/cert.pem'
elif [[ -r /etc/ssl/certs/ca-certificates.crt ]]; then
  base_config+=$'\nssl-cert-file = /etc/ssl/certs/ca-certificates.crt'
fi
job_config=$base_config
if [[ -n ${NIX_CONFIG:-} ]]; then
  job_config+=$'\n'$NIX_CONFIG
fi
job_config+=$cache_config
if [[ -n ${SETUP_NIX_EXTRA_CONFIG:-} ]]; then
  job_config+=$'\n'$SETUP_NIX_EXTRA_CONFIG
fi

reused=true
nix_bin=
if ! command -v nix >/dev/null; then
  for profile in "${NIX_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/nix}/profile" \
    "$HOME/.nix-profile" /nix/var/nix/profiles/default; do
    if [[ -x $profile/bin/nix ]]; then
      nix_bin="$profile/bin"
      export PATH="$nix_bin:$PATH"
      break
    fi
  done
fi

if ! command -v nix >/dev/null; then
  reused=false
  version=2.36.0
  case "$os:$(uname -m)" in
  Linux:x86_64)
    system=x86_64-linux
    checksum=c4d1aed088f62aa729823cffa3269e880de6ce6102fecb8909f2821eedb2f2eb
    ;;
  Linux:aarch64 | Linux:arm64)
    system=aarch64-linux
    checksum=ee696971de946d311699f6dd639cccc8c6734aec9a061b8e205de0ce6515e5ae
    ;;
  Darwin:arm64 | Darwin:aarch64)
    system=aarch64-darwin
    checksum=0e1cadd91de1580f1c5c34d9004b65c6465f0eba055a33c203c305bf68c1e765
    ;;
  *)
    echo "No bundled Nix release for $os on $(uname -m)" >&2
    exit 2
    ;;
  esac

  release="nix-$version-$system"
  archive="$work_dir/$release.tar.xz"
  echo "Downloading Nix $version for $system"
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 10 --max-time 90 --retry 2 --retry-max-time 90 \
    --output "$archive" "https://releases.nixos.org/nix/nix-$version/$release.tar.xz"
  if command -v sha256sum >/dev/null; then
    actual=$(sha256sum <"$archive")
  else
    actual=$(shasum -a 256 <"$archive")
  fi
  if [[ ${actual%% *} != "$checksum" ]]; then
    echo "SHA-256 mismatch for $release" >&2
    exit 1
  fi
  tar -xJf "$archive" -C "$work_dir"

  if [[ $os == Darwin || -d /run/systemd/system ]]; then
    # The installer starts the daemon, which reads its own configuration.
    printf '%s\n%s\n' "$base_config$cache_config" "${SETUP_NIX_EXTRA_CONFIG:-}" >"$work_dir/nix.conf"
    if [[ ${SETUP_NIX_TRUST_RUNNER:-false} == true ]]; then
      printf 'trusted-users = root %s\n' "$(id -un)" >>"$work_dir/nix.conf"
    fi
    if [[ $os == Darwin ]]; then
      cores=$(sysctl -n hw.logicalcpu)
    else
      cores=$(nproc)
    fi
    "$work_dir/$release/install" --daemon --yes --no-channel-add \
      --daemon-user-count "$((2 * cores))" --nix-extra-conf-file "$work_dir/nix.conf"
    nix_bin=/nix/var/nix/profiles/default/bin
    # Both processes read /etc/nix/nix.conf. Avoid appending the extra settings twice.
    job_config=${NIX_CONFIG:-}
  else
    job_config=$'build-users-group =\n'$job_config
    NIX_CONFIG=$job_config "$work_dir/$release/install" --no-daemon --yes --no-channel-add --no-modify-profile
    nix_bin="$HOME/.nix-profile/bin"
  fi
  export PATH="$nix_bin:$PATH"
fi

if [[ -n ${SETUP_NIX_GITHUB_TOKEN:-} ]]; then
  job_config+=$'\n'"access-tokens = github.com=$SETUP_NIX_GITHUB_TOKEN"
fi
export NIX_CONFIG=$job_config
nix store info
version=$(nix --version)
version=${version##* }
delimiter="NIX_CONFIG_${work_dir##*.}"
if [[ -n $nix_bin ]]; then
  printf '%s\n' "$nix_bin" >>"$GITHUB_PATH"
fi
printf 'NIX_CONFIG<<%s\n%s\n%s\n' "$delimiter" "$NIX_CONFIG" "$delimiter" >>"$GITHUB_ENV"
printf 'version=%s\nreused=%s\n' "$version" "$reused" >>"$GITHUB_OUTPUT"
echo "Nix $version is ready (reused: $reused)"
