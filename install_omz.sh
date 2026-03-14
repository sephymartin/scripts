#!/bin/sh
set -eu

DRY_RUN=0
USE_TUNA_MIRROR=""
SUDO_CMD=""

usage() {
  cat <<'EOF'
Usage: install_omz.sh [--dry-run] [--use-tuna-mirror] [--no-use-tuna-mirror] [--help]

Install Oh My Zsh and powerlevel10k, with an optional Tsinghua Tuna mirror.

Options:
  --dry-run            Print commands without executing them
  --use-tuna-mirror    Use Tsinghua Tuna mirrors without prompting
  --no-use-tuna-mirror Use upstream sources without prompting
  --help               Show this help message
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

run_shell() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ $1"
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
      --use-tuna-mirror)
        USE_TUNA_MIRROR=1
        ;;
      --no-use-tuna-mirror)
        USE_TUNA_MIRROR=0
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
    SUDO_CMD=""
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD="sudo"
    return 0
  fi

  log "This script must run as root or with sudo available." >&2
  exit 1
}

prompt_for_tuna_mirror() {
  if [ -n "$USE_TUNA_MIRROR" ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    USE_TUNA_MIRROR=0
    log "Non-interactive shell detected, defaulting to upstream sources."
    return 0
  fi

  printf 'Use Tsinghua Tuna mirrors for Oh My Zsh install? [y/N]: ' >&2
  if read -r answer; then
    case $(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]') in
      y|yes)
        USE_TUNA_MIRROR=1
        ;;
      *)
        USE_TUNA_MIRROR=0
        ;;
    esac
  else
    USE_TUNA_MIRROR=0
  fi
}

install_packages() {
  run_cmd ${SUDO_CMD:+$SUDO_CMD} apt update
  run_cmd ${SUDO_CMD:+$SUDO_CMD} apt install -y git zsh tmux vim curl
}

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh already installed"
    return 0
  fi

  if [ "$USE_TUNA_MIRROR" = "1" ]; then
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/install-omz.XXXXXX")
    trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
    run_cmd git clone https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git "$temp_dir/ohmyzsh"
    run_shell "cd '$temp_dir/ohmyzsh/tools' && REMOTE=https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh install.sh"
    rm -rf "$temp_dir"
    trap - EXIT HUP INT TERM
    return 0
  fi

  run_shell "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
}

install_powerlevel10k() {
  p10k_path=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
  if [ -d "$p10k_path" ]; then
    log "Powerlevel10k theme already installed"
    return 0
  fi

  run_cmd git clone --depth=1 https://gitee.com/romkatv/powerlevel10k.git "$p10k_path"
}

set_powerlevel10k_theme() {
  zshrc_file=$HOME/.zshrc

  if [ ! -f "$zshrc_file" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "+ touch $zshrc_file"
    else
      : >"$zshrc_file"
    fi
  fi

  if grep -q '^ZSH_THEME=' "$zshrc_file" 2>/dev/null; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "+ update ZSH_THEME in $zshrc_file to powerlevel10k/powerlevel10k"
    else
      sed -i'.bak' 's|^ZSH_THEME=.*$|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$zshrc_file"
    fi
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ append ZSH_THEME=\"powerlevel10k/powerlevel10k\" to $zshrc_file"
    return 0
  fi

  printf '\nZSH_THEME="powerlevel10k/powerlevel10k"\n' >>"$zshrc_file"
}

main() {
  parse_args "$@"
  require_root_or_sudo
  prompt_for_tuna_mirror

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run enabled"
  fi

  install_packages
  install_oh_my_zsh
  install_powerlevel10k
  set_powerlevel10k_theme
}

main "$@"
