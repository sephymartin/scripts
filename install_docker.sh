#!/bin/sh
set -eu

DRY_RUN=0
OS_RELEASE_FILE=${OS_RELEASE_FILE:-/etc/os-release}
SUDO=""
OS_ID=""
VERSION_CODENAME=""
TARGET_USER=""

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
    TARGET_USER=${SUDO_USER:-${USER:-}}
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    TARGET_USER=${USER:-}
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

user_in_group() {
  user_name=$1

  if command -v id >/dev/null 2>&1 && id -nG "$user_name" 2>/dev/null | grep -Eq '(^|[[:space:]])docker($|[[:space:]])'; then
    return 0
  fi

  return 1
}

init_docker_group() {
  if [ -z "$TARGET_USER" ]; then
    log "Skipping docker group initialization because the target user could not be determined."
    return 0
  fi

  if ! getent group docker >/dev/null 2>&1; then
    run_cmd ${SUDO:+$SUDO} groupadd docker
  fi

  if ! user_in_group "$TARGET_USER"; then
    run_cmd ${SUDO:+$SUDO} usermod -aG docker "$TARGET_USER"
  fi
}

print_next_steps() {
  log "Docker installation complete."
  if [ -n "$TARGET_USER" ]; then
    log "Docker group access configured for user: $TARGET_USER"
    log "Run 'newgrp docker' or log out and back in to apply the new group in your current session."
  fi
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
  init_docker_group
  print_next_steps
}

main "$@"
