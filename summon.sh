#!/bin/sh
set -eu

SUMMON_DRY_RUN="${SUMMON_DRY_RUN:-0}"
SUMMON_HOME="${SUMMON_HOME:-$HOME}"
SUMMON_BIN_DIR="${SUMMON_BIN_DIR:-$SUMMON_HOME/.local/bin}"
SUMMON_CONFIG_DIR="${SUMMON_CONFIG_DIR:-$SUMMON_HOME/.config}"
SUMMON_MISE_DIR="${SUMMON_MISE_DIR:-$SUMMON_CONFIG_DIR/mise}"
SUMMON_MISE_CONFIG="${SUMMON_MISE_CONFIG:-$SUMMON_MISE_DIR/config.toml}"
SUMMON_MISE_LOCK="${SUMMON_MISE_LOCK:-$SUMMON_MISE_DIR/mise.lock}"
SUMMON_REPO_REF="${SUMMON_REPO_REF:-main}"
SUMMON_SOURCE_DIR="${SUMMON_SOURCE_DIR:-}"
SUMMON_OMARCHY_REF="${SUMMON_OMARCHY_REF:-b2d95ee24b09667e652674d8b33eeecad0f528f2}"

MISE_BIN="${MISE_BIN:-$SUMMON_BIN_DIR/mise}"
BUN_INSTALL="${BUN_INSTALL:-$SUMMON_HOME/.bun}"

export BUN_INSTALL
export PATH="$SUMMON_BIN_DIR:$BUN_INSTALL/bin:$PATH"

log() {
  printf '%s\n' "summon: $*"
}

run() {
  if [ "$SUMMON_DRY_RUN" = "1" ]; then
    printf 'DRY-RUN:'
    printf ' %s' "$@"
    printf '\n'
  else
    "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64' ;;
    aarch64 | arm64) printf 'arm64' ;;
    *)
      log "unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac
}

ensure_dir() {
  [ -d "$1" ] || run mkdir -p "$1"
}

download() {
  download_url="$1"
  download_dest="$2"
  ensure_dir "$(dirname "$download_dest")"
  tmp="${download_dest}.tmp.$$"
  trap 'rm -f "$tmp"' HUP INT TERM EXIT
  if need_cmd curl; then
    run curl -fsSL --proto '=https' --tlsv1.2 "$download_url" -o "$tmp"
  elif need_cmd wget; then
    run wget -qO "$tmp" "$download_url"
  else
    log "curl or wget is required"
    exit 1
  fi
  if [ "$SUMMON_DRY_RUN" != "1" ]; then
    if [ -f "$download_dest" ] && [ ! -f "${download_dest}.bak" ]; then
      cp "$download_dest" "${download_dest}.bak"
    fi
    mv "$tmp" "$download_dest"
  fi
  trap - HUP INT TERM EXIT
}

install_file() {
  src="$1"
  dest="$2"
  ensure_dir "$(dirname "$dest")"
  if [ "$SUMMON_DRY_RUN" = "1" ]; then
    log "would install $src to $dest"
    return 0
  fi
  if [ -f "$dest" ] && [ ! -f "${dest}.bak" ]; then
    cp "$dest" "${dest}.bak"
  fi
  cp "$src" "$dest"
}

append_once() {
  file="$1"
  line="$2"
  ensure_dir "$(dirname "$file")"
  if [ "$SUMMON_DRY_RUN" = "1" ]; then
    log "would ensure line in $file: $line"
    return 0
  fi
  touch "$file"
  grep -Fqx "$line" "$file" || printf '%s\n' "$line" >>"$file"
}

prepend_managed_block() {
  file="$1"
  block_name="$2"
  block_content="$3"
  start="# summon: begin $block_name"
  end="# summon: end $block_name"
  ensure_dir "$(dirname "$file")"
  if [ "$SUMMON_DRY_RUN" = "1" ]; then
    log "would ensure $block_name block near top of $file"
    return 0
  fi
  touch "$file"
  tmp="${file}.tmp.$$"
  {
    printf '%s\n' "$start"
    printf '%s\n' "$block_content"
    printf '%s\n\n' "$end"
    awk -v start="$start" -v end="$end" '
      $0 == start { skip = 1; next }
      $0 == end { skip = 0; next }
      skip != 1 { print }
    ' "$file"
  } >"$tmp"
  mv "$tmp" "$file"
}

install_system_packages() {
  if [ "$(id -u)" -ne 0 ]; then
    log "not root; skipping system packages"
    return 0
  fi

  if need_cmd apt-get; then
    run apt-get update
    run apt-get install -y ca-certificates curl git tar gzip unzip xz-utils bash tmux build-essential
  elif need_cmd dnf; then
    run dnf install -y ca-certificates curl git tar gzip unzip xz bash tmux gcc gcc-c++ make
  elif need_cmd yum; then
    run yum install -y ca-certificates curl git tar gzip unzip xz bash tmux gcc gcc-c++ make
  elif need_cmd apk; then
    run apk add --no-cache ca-certificates curl git tar gzip unzip xz bash tmux build-base
  else
    log "no supported package manager found; skipping system packages"
  fi
}

install_mise() {
  if [ -x "$MISE_BIN" ] || need_cmd mise; then
    log "mise already installed"
    return 0
  fi
  ensure_dir "$SUMMON_BIN_DIR"
  if [ -n "$SUMMON_SOURCE_DIR" ]; then
    install_file "$SUMMON_SOURCE_DIR/bin/mise" "$MISE_BIN"
  else
    base="https://raw.githubusercontent.com/upamune/summon/$SUMMON_REPO_REF"
    download "$base/bin/mise" "$MISE_BIN"
  fi
  run chmod +x "$MISE_BIN"
  if [ "$SUMMON_DRY_RUN" != "1" ]; then
    "$MISE_BIN" version >/dev/null
  fi
}

install_mise_config() {
  if [ -n "$SUMMON_SOURCE_DIR" ]; then
    install_file "$SUMMON_SOURCE_DIR/mise.toml" "$SUMMON_MISE_CONFIG"
    install_file "$SUMMON_SOURCE_DIR/mise.lock" "$SUMMON_MISE_LOCK"
  else
    base="https://raw.githubusercontent.com/upamune/summon/$SUMMON_REPO_REF"
    download "$base/mise.toml" "$SUMMON_MISE_CONFIG"
    download "$base/mise.lock" "$SUMMON_MISE_LOCK"
  fi
}

mise_exec() {
  if [ -x "$MISE_BIN" ]; then
    run "$MISE_BIN" "$@"
  else
    run mise "$@"
  fi
}

mise_direct() {
  if [ -x "$MISE_BIN" ]; then
    "$MISE_BIN" "$@"
  else
    mise "$@"
  fi
}

install_mise_tools() {
  mise_exec trust --yes "$SUMMON_MISE_CONFIG"
  mise_exec install --yes --locked
}

install_omarchy_configs() {
  omarchy_base="https://raw.githubusercontent.com/basecamp/omarchy/$SUMMON_OMARCHY_REF"
  download "$omarchy_base/default/bashrc" "$SUMMON_HOME/.bashrc"
  install_omarchy_bash_defaults
  ensure_dir "$SUMMON_CONFIG_DIR/tmux"
  download "$omarchy_base/config/tmux/tmux.conf" "$SUMMON_CONFIG_DIR/tmux/tmux.conf"
  [ -e "$SUMMON_HOME/.tmux.conf" ] || run ln -s "$SUMMON_CONFIG_DIR/tmux/tmux.conf" "$SUMMON_HOME/.tmux.conf"
}

install_omarchy_bash_defaults() {
  omarchy_bash_base="https://raw.githubusercontent.com/basecamp/omarchy/$SUMMON_OMARCHY_REF/default/bash"
  omarchy_bash_dest="$SUMMON_HOME/.local/share/omarchy/default/bash"
  ensure_dir "$omarchy_bash_dest/fns"
  for file in aliases completions envs functions init inputrc rc shell; do
    download "$omarchy_bash_base/$file" "$omarchy_bash_dest/$file"
  done
  for file in compression drives ssh-port-forwarding tmux transcoding worktrees; do
    download "$omarchy_bash_base/fns/$file" "$omarchy_bash_dest/fns/$file"
  done
}

configure_mise_shell() {
  # shellcheck disable=SC2016
  prepend_managed_block "$SUMMON_HOME/.bashrc" "mise" 'export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"'
}

install_starship() {
  if [ "$SUMMON_DRY_RUN" = "1" ]; then
    log "would apply starship pure preset"
  else
    mise_direct exec -- starship preset pure-preset -o "$SUMMON_CONFIG_DIR/starship.toml"
  fi
  # shellcheck disable=SC2016
  append_once "$SUMMON_HOME/.bashrc" 'eval "$(starship init bash)"'
}

install_atuin_shell() {
  # shellcheck disable=SC2016
  append_once "$SUMMON_HOME/.bashrc" 'eval "$(atuin init bash)"'
}

configure_bun_path() {
  # shellcheck disable=SC2016
  append_once "$SUMMON_HOME/.bashrc" 'export PATH="$HOME/.bun/bin:$PATH"'
}

configure_git() {
  run git config --global user.email "info@serizawa.me"
  run git config --global user.name "Yu SERIZAWA(@upamune)"
}

install_node_clis() {
  mise_exec exec -- bun install -g github:upamune/mypi
}

main() {
  arch="$(detect_arch)"
  log "setting up linux-$arch under $SUMMON_HOME"
  install_system_packages
  install_mise
  install_mise_config
  install_mise_tools
  install_omarchy_configs
  configure_mise_shell
  install_starship
  install_atuin_shell
  configure_bun_path
  configure_git
  install_node_clis
  log "done"
  log "restart your shell with: exec bash"
}

main "$@"
