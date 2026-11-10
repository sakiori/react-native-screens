#!/bin/sh
# Installs pinned tools into <dir>/bin, each download checked against its SHA-256, with no
# fallback. Host: x86_64 Linux, the group's Linux runner.
#
# usage: .gitlab/scripts/install-tools.sh <dir> <tool>...
#   tools: shellcheck, git-intake
set -eu

dir=${1:?usage: install-tools.sh <dir> <tool>...}
shift
host="$(uname -s)-$(uname -m)"
[ "$host" = Linux-x86_64 ] || { echo "the pinned tools are for x86_64 Linux, not $host" >&2; exit 1; }
mkdir -p "$dir/bin"
dir=$(cd "$dir" && pwd -P)

fetch() { # <url> <sha256> <file>
  curl --fail --silent --show-error --location --retry 4 --proto '=https' --tlsv1.2 --output "$3" "$1"
  echo "$2  $3" | sha256sum --check --strict --quiet - || { rm -f "$3"; echo "$1 does not match its pinned SHA-256" >&2; exit 1; }
}

# <url> <sha256> <path of the executable in the archive>
unpack() {
  archive="$dir/download"
  fetch "$1" "$2" "$archive"
  tar -xf "$archive" -C "$dir/bin" --strip-components="$(printf '%s' "$3" | tr -cd / | wc -c)" "$3"
  rm "$archive"
}

for tool in "$@"; do
  case "$tool" in
    shellcheck)
      version=0.11.0
      unpack "https://github.com/koalaman/shellcheck/releases/download/v$version/shellcheck-v$version.linux.x86_64.tar.xz" \
        8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 \
        "shellcheck-v$version/shellcheck"
      ;;
    git-intake)
      # The release is pinned in .gitlab-ci.yml, GIT_INTAKE_VERSION and its archive's checksum.
      version=${GIT_INTAKE_VERSION:?GIT_INTAKE_VERSION is not set}
      sum=${GIT_INTAKE_SHA256_X86_64_LINUX:?GIT_INTAKE_SHA256_X86_64_LINUX is not set}
      name="git-intake-v$version-x86_64-unknown-linux-musl.tar.gz"
      unpack "https://gitlab.com/sakiori-oss/git-intake/-/releases/v$version/downloads/binaries/$name" "$sum" git-intake
      ;;
    *)
      echo "unknown tool: $tool" >&2
      exit 1
      ;;
  esac
  echo "installed $tool"
done
