#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
repo_dir="$PWD"

fail() {
  echo "test: $*" >&2
  exit 1
}

contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$label: expected '$needle' in '$haystack'"
}

assert_cmd_contains() {
  local expected="$1"
  local label="$2"
  shift 2
  local output
  output="$("$@" 2>&1)"
  contains "$output" "$expected" "$label"
}

sh -n summon.sh
bash -n test.sh
bash -n bin/mise

lint_root="$(mktemp -d)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$lint_root" "$tmp_home"' EXIT
tmp_config="$tmp_home/.config"
tmp_data="$tmp_home/.local/share"
tmp_cache="$tmp_home/.cache"
mkdir -p "$tmp_config" "$tmp_data" "$tmp_cache"

HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_config" XDG_DATA_HOME="$tmp_data" XDG_CACHE_HOME="$tmp_cache" "$repo_dir/bin/mise" exec --locked -C "$repo_dir" shellcheck@0.11.0 -- shellcheck "$repo_dir/summon.sh" "$repo_dir/test.sh"
HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_config" XDG_DATA_HOME="$tmp_data" XDG_CACHE_HOME="$tmp_cache" "$repo_dir/bin/mise" exec --locked -C "$repo_dir" shfmt@3.13.1 -- shfmt -d -i 2 -ci "$repo_dir/summon.sh" "$repo_dir/test.sh"

! grep -q 'npm install -g' summon.sh || fail "summon.sh must not use npm install -g"
! grep -qi 'sudo' summon.sh Dockerfile || fail "summon must not require sudo"
! grep -q '"latest"' mise.toml || fail "mise.toml must not use latest"
grep -q '"http:herdr"' mise.toml || fail "mise.toml must manage herdr"
grep -q '"http:neovim"' mise.toml || fail "mise.toml must manage neovim"
[ -s mise.lock ] || fail "mise.lock is required"

HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_config" XDG_DATA_HOME="$tmp_data" XDG_CACHE_HOME="$tmp_cache" SUMMON_HOME="$tmp_home" SUMMON_SOURCE_DIR="$repo_dir" SUMMON_MYPI_MODE=skip SUMMON_SHELL=bash sh "$repo_dir/summon.sh"

mise="$tmp_home/.local/bin/mise"
[ -x "$mise" ] || fail "mise was not installed"

run_mise() {
  HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_config" XDG_DATA_HOME="$tmp_data" XDG_CACHE_HOME="$tmp_cache" "$mise" exec -- "$@"
}

assert_cmd_contains "1.3.9" "bun version" run_mise bun --version
assert_cmd_contains "v24.12.0" "node version" run_mise node --version
assert_cmd_contains "go1.26.3" "go version" run_mise go version
assert_cmd_contains "1.89.0" "rust version" run_mise rustc --version
assert_cmd_contains "1.25.1" "starship version" run_mise starship --version
assert_cmd_contains "18.16.1" "atuin version" run_mise atuin --version
assert_cmd_contains "0.9.27" "uv version" run_mise uv --version
assert_cmd_contains "v0.12.2" "neovim version" run_mise nvim --version
assert_cmd_contains "0.11.0" "shellcheck version" run_mise shellcheck --version
assert_cmd_contains "3.13.1" "shfmt version" run_mise shfmt --version
assert_cmd_contains "0.5.8" "herdr version" run_mise herdr --version
assert_cmd_contains "0.130.0" "codex version" run_mise codex --version

PATH="$tmp_home/.bun/bin:$PATH" command -v mypi >/dev/null || fail "mypi was not installed"
PATH="$tmp_home/.bun/bin:$PATH" command -v pi >/dev/null || fail "pi was not installed"
assert_cmd_contains "tmux" "tmux version" tmux -V

grep -q 'mise activate bash' "$tmp_home/.bashrc" || fail "bashrc must initialize mise"
grep -q '.bun/bin' "$tmp_home/.bashrc" || fail "bashrc must add bun global bin"
grep -q 'starship init bash' "$tmp_home/.bashrc" || fail "bashrc must initialize starship"
grep -q 'atuin init bash' "$tmp_home/.bashrc" || fail "bashrc must initialize atuin"
grep -q 'tmux new-session -A -s main' "$tmp_home/.bashrc" || fail "bashrc must auto attach tmux"
HOME="$tmp_home" bash -ic 'true' >/dev/null 2>&1 || fail "bashrc must load without errors"

HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_config" XDG_DATA_HOME="$tmp_data" XDG_CACHE_HOME="$tmp_cache" SUMMON_HOME="$tmp_home" SUMMON_SOURCE_DIR="$repo_dir" SUMMON_MYPI_MODE=skip SUMMON_SHELL=zsh sh "$repo_dir/summon.sh"

grep -q 'mise activate zsh' "$tmp_home/.zshrc" || fail "zshrc must initialize mise"
grep -q '.bun/bin' "$tmp_home/.zshrc" || fail "zshrc must add bun global bin"
grep -q 'starship init zsh' "$tmp_home/.zshrc" || fail "zshrc must initialize starship"
grep -q 'atuin init zsh' "$tmp_home/.zshrc" || fail "zshrc must initialize atuin"
grep -q 'tmux new-session -A -s main' "$tmp_home/.zshrc" || fail "zshrc must auto attach tmux"
if command -v zsh >/dev/null 2>&1; then
  HOME="$tmp_home" zsh -ic 'true' >/dev/null 2>&1 || fail "zshrc must load without errors"
fi

[ "$(HOME="$tmp_home" git config --global user.email)" = "info@serizawa.me" ] || fail "git email mismatch"
[ "$(HOME="$tmp_home" git config --global user.name)" = "Yu SERIZAWA(@upamune)" ] || fail "git name mismatch"

echo "test: ok"
