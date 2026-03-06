#!/bin/bash

sudo apt update && sudo apt upgrade -y || echo "WARN: apt update/upgrade failed"
cargo install-update -a || echo "WARN: cargo install-update failed"
mise self-update -y || echo "WARN: mise self-update failed"
mise upgrade || echo "WARN: mise upgrade failed"
nvim --headless "+Lazy! update" +qa || echo "WARN: nvim Lazy update failed"
nvim --headless -c 'autocmd User MasonUpdateAllComplete quitall' -c 'MasonUpdateAll' || echo "WARN: nvim Mason update failed"
