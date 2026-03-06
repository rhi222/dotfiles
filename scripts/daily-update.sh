#!/bin/bash

sudo xargs -a apt-packages.txt apt install -y
sudo apt update && sudo apt upgrade -y
cargo install-update -a
mise self-update -y
mise upgrade
nvim --headless "+Lazy! update" +qa
nvim --headless -c 'autocmd User MasonUpdateAllComplete quitall' -c 'MasonUpdateAll'
