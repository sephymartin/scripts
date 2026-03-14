#!/bin/sh
set -eu

DRY_RUN=0
OS_RELEASE_FILE=${OS_RELEASE_FILE:-/etc/os-release}
SUDO=""
OS_ID=""
VERSION_CODENAME=""

usage() {
  cat <<'EOF'
Usage: install_docker.sh [--dry-run] [--help]

Install Docker Engine stable on Debian using Docker's official APT repository.

Options:
  --dry-run  Print commands without executing them
  --help     Show this help message
EOF
}

log() {
  printf '%s\n' "$*"
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ $*"
    return 0
  fi
  "$@"
}

run_sh() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ $*"
    return 0
  fi
  sh -c "$1"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        log "Unsupported argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

require_root_or_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    return 0
  fi

  log "This script must run as root or with sudo available." >&2
  exit 1
}

detect_os() {
  if [ ! -f "$OS_RELEASE_FILE" ]; then
    log "Cannot find os-release file: $OS_RELEASE_FILE" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "$OS_RELEASE_FILE"

  OS_ID=${ID:-}
  VERSION_CODENAME=${VERSION_CODENAME:-}
}

assert_supported_os() {
  case "$OS_ID" in
    debian)
      [ -n "$VERSION_CODENAME" ] || {
        log "VERSION_CODENAME is missing from $OS_RELEASE_FILE" >&2
        exit 1
      }
      ;;
    ubuntu)
      log "Ubuntu support is reserved for a future version." >&2
      exit 1
      ;;
    *)
      log "Unsupported operating system: ${OS_ID:-unknown}. Only Debian is supported." >&2
      exit 1
      ;;
  esac
}

remove_conflicting_packages() {
  run_sh "$SUDO apt remove -y docker.io docker-compose docker-doc podman-docker containerd runc || true"
}

install_prerequisites() {
  run_cmd ${SUDO:+$SUDO} apt-get update
  run_cmd ${SUDO:+$SUDO} apt-get install -y ca-certificates curl
}

setup_docker_repo_debian() {
  run_cmd ${SUDO:+$SUDO} install -m 0755 -d /etc/apt/keyrings
  run_cmd ${SUDO:+$SUDO} curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  run_cmd ${SUDO:+$SUDO} chmod a+r /etc/apt/keyrings/docker.asc

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ ${SUDO:+$SUDO }tee /etc/apt/sources.list.d/docker.sources >/dev/null <<'EOF'"
    log "Types: deb"
    log "URIs: https://download.docker.com/linux/debian"
    log "Suites: $VERSION_CODENAME"
    log "Components: stable"
    log "Signed-By: /etc/apt/keyrings/docker.asc"
    log "EOF"
    return 0
  fi

  ${SUDO:+$SUDO }tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
}

install_docker_packages_debian() {
  run_cmd ${SUDO:+$SUDO} apt-get update
  run_cmd ${SUDO:+$SUDO} apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

print_next_steps() {
  log "Docker installation complete."
  log "Verify with: docker --version"
  log "Verify with: docker compose version"
}

main() {
  parse_args "$@"
  require_root_or_sudo
  detect_os
  assert_supported_os
  remove_conflicting_packages
  install_prerequisites
  setup_docker_repo_debian
  install_docker_packages_debian
  print_next_steps
}

main "$@"
