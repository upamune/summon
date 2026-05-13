#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

fail() {
  echo "test: $*" >&2
  exit 1
}

sh -n summon.sh
bash -n test.sh
bash -n bin/mise

grep -q 'SUMMON_DRY_RUN' summon.sh || fail "summon.sh must support dry-run"
grep -q 'SUMMON_MISE_CONFIG' summon.sh || fail "summon.sh must install global mise config"
grep -q 'mise.lock' summon.sh || fail "summon.sh must install global mise lock"
grep -q -- '--locked' summon.sh || fail "mise install must use the lockfile"
grep -q 'basecamp/omarchy' summon.sh || fail "summon.sh must fetch omarchy config"
grep -q 'pure-preset' summon.sh || fail "summon.sh must configure starship pure preset"
grep -q 'atuin init bash' summon.sh || fail "summon.sh must initialize atuin"
grep -q 'info@serizawa.me' summon.sh || fail "summon.sh must configure git email"
grep -q 'Yu SERIZAWA(@upamune)' summon.sh || fail "summon.sh must configure git name"
grep -q 'bin/mise' summon.sh || fail "summon.sh must install mise through generated bootstrap"
grep -q 'github:upamune/mypi' summon.sh || fail "summon.sh must install mypi"
grep -q '@openai/codex' summon.sh || fail "summon.sh must install codex cli"
grep -q '"github:ogulcancelik/herdr" = "0.5.8"' mise.toml || fail "mise.toml must manage herdr"
! grep -q '"latest"' mise.toml || fail "mise.toml must not use latest"
[ -s mise.lock ] || fail "mise.lock is required"

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

SUMMON_DRY_RUN=1 SUMMON_HOME="$tmp_home" HOME="$tmp_home" sh ./summon.sh >"$tmp_home/dry-run.log"
grep -q 'linux-' "$tmp_home/dry-run.log" || fail "dry-run did not execute"
grep -q 'mise.toml' "$tmp_home/dry-run.log" || fail "dry-run did not cover mise config"
grep -q 'mise.lock' "$tmp_home/dry-run.log" || fail "dry-run did not cover mise lock"

echo "test: ok"
