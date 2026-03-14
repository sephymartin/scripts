#!/bin/sh
set -eu

DRY_RUN=0
USE_TUNA_MIRROR=""
SUDO_CMD=""
REQUIRED_PLUGINS="git tmux zoxide fzf-tab zsh-autosuggestions zsh-completions fast-syntax-highlighting"

usage() {
  cat <<'EOF'
Usage: init_debian_user_env.sh [--dry-run] [--use-tuna-mirror] [--no-use-tuna-mirror] [--help]

Initialize a Debian-like user environment with Oh My Zsh and required plugins.

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

  printf 'Use Tsinghua Tuna mirrors for Oh My Zsh and plugins? [y/N]: ' >&2
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

get_plugin_url() {
  plugin_name=$1

  if [ "$USE_TUNA_MIRROR" = "1" ]; then
    printf 'https://mirrors.tuna.tsinghua.edu.cn/git/%s.git\n' "$plugin_name"
    return 0
  fi

  case "$plugin_name" in
    fast-syntax-highlighting)
      printf '%s\n' "https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
      ;;
    fzf-tab)
      printf '%s\n' "https://github.com/Aloxaf/fzf-tab.git"
      ;;
    zsh-autosuggestions)
      printf '%s\n' "https://github.com/zsh-users/zsh-autosuggestions.git"
      ;;
    zsh-completions)
      printf '%s\n' "https://github.com/zsh-users/zsh-completions.git"
      ;;
    *)
      log "Unknown plugin: $plugin_name" >&2
      exit 1
      ;;
  esac
}

build_plugin_block() {
  plugin_list=$1
  printf 'plugins=(\n'
  for plugin in $plugin_list; do
    printf '  %s\n' "$plugin"
  done
  printf ')\n'
}

extract_existing_plugins() {
  zshrc_file=$1

  [ -f "$zshrc_file" ] || return 0

  awk '
    function flush_buffer() {
      gsub(/plugins=/, " ", buffer)
      gsub(/[()]/, " ", buffer)
      count = split(buffer, parts, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        if (parts[i] != "") {
          print parts[i]
        }
      }
      buffer = ""
    }

    {
      line = $0
      sub(/#.*/, "", line)

      if (!capturing && line ~ /^plugins=[[:space:]]*\(/) {
        capturing = 1
      }

      if (capturing) {
        buffer = buffer " " line
        if (line ~ /\)/) {
          flush_buffer()
          exit
        }
      }
    }
  ' "$zshrc_file"
}

merge_plugins() {
  existing_plugins=$1
  merged_plugins=""

  for plugin in $existing_plugins $REQUIRED_PLUGINS; do
    [ -n "$plugin" ] || continue
    case " $merged_plugins " in
      *" $plugin "*) ;;
      *)
        merged_plugins="${merged_plugins}${merged_plugins:+ }$plugin"
        ;;
    esac
  done

  printf '%s\n' "$merged_plugins"
}

ensure_plugins_enabled() {
  zshrc_file=$1

  if [ ! -f "$zshrc_file" ]; then
    : >"$zshrc_file"
  fi

  existing_plugins=$(extract_existing_plugins "$zshrc_file" | tr '\n' ' ' | xargs 2>/dev/null || true)
  merged_plugins=$(merge_plugins "$existing_plugins")
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")
  block_file=$(mktemp "${TMPDIR:-/tmp}/zshrc-block.XXXXXX")
  build_plugin_block "$merged_plugins" >"$block_file"

  awk -v block_file="$block_file" '
    function print_block() {
      while ((getline line < block_file) > 0) {
        print line
      }
      close(block_file)
    }

    BEGIN {
      capturing = 0
      replaced = 0
    }

    {
      if (!replaced && $0 ~ /^plugins=[[:space:]]*\(/) {
        capturing = 1
        print_block()
        if ($0 ~ /\)/) {
          capturing = 0
          replaced = 1
        }
        next
      }

      if (capturing) {
        if ($0 ~ /\)/) {
          capturing = 0
          replaced = 1
        }
        next
      }

      print
    }

    END {
      if (!replaced) {
        if (NR > 0) {
          print ""
        }
        print_block()
      }
    }
  ' "$zshrc_file" >"$tmp_file"

  rm -f "$block_file"
  mv "$tmp_file" "$zshrc_file"
}

install_packages() {
  run_cmd ${SUDO_CMD:+$SUDO_CMD} apt install -y git tmux zoxide fzf unzip zip zsh curl
}

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh already installed"
    return 0
  fi

  if [ "$USE_TUNA_MIRROR" = "1" ]; then
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/init-user-env.XXXXXX")
    trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
    run_cmd git clone https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git "$temp_dir/ohmyzsh"
    run_shell "cd '$temp_dir/ohmyzsh/tools' && REMOTE=https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh install.sh"
    rm -rf "$temp_dir"
    trap - EXIT HUP INT TERM
    return 0
  fi

  run_shell "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
}

install_plugins() {
  custom_plugins_dir=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins
  run_cmd mkdir -p "$custom_plugins_dir"

  for plugin in fast-syntax-highlighting fzf-tab zsh-autosuggestions zsh-completions; do
    plugin_dir=$custom_plugins_dir/$plugin
    if [ -d "$plugin_dir" ]; then
      log "$plugin already installed"
      continue
    fi
    run_cmd git clone "$(get_plugin_url "$plugin")" "$plugin_dir"
  done
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
  install_plugins

  if [ "$DRY_RUN" -eq 0 ]; then
    ensure_plugins_enabled "$HOME/.zshrc"
  else
    log "+ ensure requested plugins exist in $HOME/.zshrc"
  fi
}

if [ "${INIT_DEBIAN_USER_ENV_LIB_ONLY:-0}" -ne 1 ]; then
  main "$@"
fi
