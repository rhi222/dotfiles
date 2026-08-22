#!/bin/bash
# daily-update.sh向けの薄い入口。remote stateとcacheの判定はdotctlが担う。

fisher_update() {
  if ! command -v fish >/dev/null 2>&1; then
    echo "fish not found, skipping"
    return 0
  fi
  if ! fish -c 'functions -q fisher' >/dev/null 2>&1; then
    echo "fisher not installed, skipping (run scripts/setup-fish-plugins.sh)"
    return 0
  fi
  if ! command -v dotctl >/dev/null 2>&1; then
    echo "dotctl not found (run scripts/setup-dotctl.sh)" >&2
    return 1
  fi
  dotctl fisher-update
}
